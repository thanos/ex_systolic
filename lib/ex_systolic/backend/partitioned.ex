defmodule ExSystolic.Backend.Partitioned do
  @moduledoc """
  A tile-based parallel execution backend using Task.async_stream.

  The partitioned backend divides the array into rectangular tiles and
  dispatches tile computations in parallel.  Each tick follows the
  Bulk Synchronous Parallel (BSP) model:

  1. **Inject** -- push external input streams into boundary links
  2. **Read** -- read all link buffers (globally, before any PE executes)
  3. **Dispatch** -- submit tile PE computations in parallel
  4. **Collect** -- gather all tile results
  5. **Write** -- write all outputs into link buffers
  6. **Record** -- merge trace events

  ## Determinism guarantee

  Even though tiles execute in parallel within a tick, the BSP barrier
  ensures that all tiles see the same frozen inputs for a given tick.
  No tile reads data produced by another tile in the same tick.  This
  means the partitioned backend produces **identical results** to the
  interpreted backend for the same inputs.

  ## Options

  - `:ticks` -- number of ticks to run (required)
  - `:tile_rows` -- rows per tile (default: array rows, i.e. single tile)
  - `:tile_cols` -- cols per tile (default: array cols, i.e. single tile)

  ## When to use

  Use the partitioned backend when:

  - The array is large enough that parallelism helps (> 8x8)
  - You need multi-core throughput
  - You have confirmed determinism parity with the interpreted backend

  For small arrays or debugging, the interpreted backend is simpler and
  has less overhead.

  ## Examples

      iex> alias ExSystolic.{Array, Backend.Partitioned, PE.MAC}
      iex> array = Array.new(rows: 2, cols: 2) |> Array.fill(MAC) |> Array.connect(:west_to_east) |> Array.connect(:north_to_south)
      iex> array = Array.input(array, :west, [{{0,0}, [1,2]}, {{1,0}, [3,4]}])
      iex> array = Array.input(array, :north, [{{0,0}, [5,7]}, {{0,1}, [6,8]}])
      iex> result = Partitioned.run(array, ticks: 5)
      iex> result.tick
      5

  """

  @behaviour ExSystolic.Backend

  alias ExSystolic.{Array, TilePartitioner, Trace}
  alias ExSystolic.Backend.Interpreted

  @doc """
  Runs the array for the given number of ticks using tile-based parallel
  execution.

  Returns the final array state, which includes the updated PEs, links,
  tick counter, and trace.
  """
  @impl true
  @spec run(Array.t(), keyword()) :: Array.t()
  def run(array, opts) do
    ticks = Keyword.fetch!(opts, :ticks)
    tile_opts = Keyword.take(opts, [:tile_rows, :tile_cols])

    Enum.reduce(1..ticks//1, array, fn _, acc -> step(acc, tile_opts) end)
  end

  @doc """
  Executes a single tick using the partitioned backend.

  This is the BSP step: inject, read, dispatch, collect, write, record,
  advance.  Links are managed globally (like the interpreted backend);
  only PE execution is parallelized across tiles.
  """
  @spec step(Array.t(), keyword()) :: Array.t()
  def step(array, tile_opts \\ []) do
    %{
      pes: pes,
      links: links,
      tick: tick,
      trace: trace,
      trace_enabled: trace_enabled,
      input_streams: input_streams
    } = array

    {links_after_inject, remaining_streams} = inject_inputs(links, input_streams)

    input_ports =
      links_after_inject
      |> Enum.map(& &1.to)
      |> Enum.uniq()

    {inputs_map, drained_links} = read_all_links(links_after_inject, input_ports)

    tiles = TilePartitioner.partition(%{array | pes: pes}, tile_opts)

    tile_results = dispatch_tiles(tiles, inputs_map, tick, trace_enabled)

    {new_pes, tick_outputs, all_events} = collect_results(tile_results, pes)

    {new_links, _remaining} = Interpreted.write_outputs(drained_links, tick_outputs, %{})

    new_trace =
      if trace_enabled do
        Enum.reduce(all_events, trace, &Trace.record(&2, &1))
      else
        trace
      end

    %{
      array
      | pes: new_pes,
        links: new_links,
        tick: tick + 1,
        trace: new_trace,
        input_streams: remaining_streams
    }
  end

  defp inject_inputs(links, input_streams) do
    Enum.reduce(input_streams, {links, %{}}, fn {key, stream}, {acc_links, acc_streams} ->
      inject_one(acc_links, acc_streams, key, stream)
    end)
  end

  defp inject_one(links, streams, {coord, port} = key, [val | rest]) do
    idx = Enum.find_index(links, fn l -> l.to == {coord, port} end)
    do_inject(links, streams, key, idx, val, rest)
  end

  defp inject_one(links, streams, _key, _stream), do: {links, streams}

  defp do_inject(links, streams, _key, nil, _val, _rest), do: {links, streams}

  defp do_inject(links, streams, key, idx, val, rest) do
    link = Enum.at(links, idx)

    case ExSystolic.Link.write(link, val) do
      {:ok, new_link} ->
        new_links = List.replace_at(links, idx, new_link)
        new_streams = if rest == [], do: streams, else: Map.put(streams, key, rest)
        {new_links, new_streams}

      {:error, :full} ->
        {links, Map.put(streams, key, [val | rest])}
    end
  end

  defp read_all_links(links, input_ports) do
    link_to_idx =
      for {link, idx} <- Enum.with_index(links), into: %{}, do: {link.to, idx}

    Enum.reduce(input_ports, {%{}, links}, fn {_coord, _port} = key, {acc_inputs, acc_links} ->
      idx = Map.get(link_to_idx, key)

      case idx do
        nil ->
          {Map.put(acc_inputs, key, :empty), acc_links}

        i ->
          link = Enum.at(acc_links, i)
          {val, new_link} = ExSystolic.Link.read(link)
          new_links = List.replace_at(acc_links, i, new_link)
          {Map.put(acc_inputs, key, val), new_links}
      end
    end)
  end

  defp dispatch_tiles(tiles, inputs_map, tick, trace_enabled) do
    tiles
    |> Task.async_stream(
      fn tile ->
        Interpreted.execute_tick(tile.pes, inputs_map, tick, trace_enabled)
      end,
      max_concurrency: System.schedulers_online(),
      ordered: false
    )
    |> Enum.zip(tiles)
    |> Enum.map(fn {{:ok, result}, tile} -> {tile, result} end)
  end

  defp collect_results(tile_results, _original_pes) do
    {new_pes, tick_outputs, all_events} =
      Enum.reduce(tile_results, {%{}, %{}, []}, fn {_tile, {tile_pes, tile_outputs, tile_events}},
                                                   {acc_pes, acc_outs, acc_evts} ->
        {Map.merge(acc_pes, tile_pes), Map.merge(acc_outs, tile_outputs), tile_events ++ acc_evts}
      end)

    {new_pes, tick_outputs, all_events}
  end
end
