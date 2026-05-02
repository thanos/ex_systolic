defmodule ExSystolic.Clock do
  @moduledoc """
  The clock drives systolic array execution tick by tick.

  The clock is the orchestrator: it delegates to the selected backend's
  tick sequence in strict order, for as many ticks as requested.

  ## Backend selection

  By default, the interpreted (single-process) backend is used.  You can
  select the partitioned (tile-based parallel) backend via the `:backend`
  option:

      # Interpreted (default)
      Clock.run(array, ticks: 10)

      # Partitioned
      Clock.run(array, ticks: 10, backend: :partitioned, tile_rows: 4, tile_cols: 4)

  Both backends produce **identical results** for the same inputs.

  ## Determinism

  Because the interpreted backend is purely functional and the partitioned
  backend uses BSP barriers (no interleaving between compute and
  communication), running `Clock.run(array, ticks: n)` always produces
  the same result for the same inputs, regardless of backend choice.

  ## API

  - `run/2` -- execute N ticks
  - `step/1` -- execute exactly one tick (interpreted only)
  """

  alias ExSystolic.Backend.Interpreted
  alias ExSystolic.Backend.Partitioned
  alias ExSystolic.Trace

  @doc """
  Runs the array for the given number of ticks.

  Returns the final array state, which includes the updated PEs, links,
  tick counter, and trace.

  ## Options

  - `:ticks` -- number of ticks (required)
  - `:backend` -- `:interpreted` (default) or `:partitioned`
  - `:tile_rows` -- rows per tile (partitioned only)
  - `:tile_cols` -- cols per tile (partitioned only)

  ## Examples

      iex> alias ExSystolic.{Array, Clock, PE.MAC}
      iex> array = Array.new(rows: 1, cols: 1) |> Array.fill(MAC) |> Array.connect(:west_to_east) |> Array.connect(:north_to_south)
      iex> array = Array.input(array, :west, [{{0,0}, [3, 2]}])
      iex> array = Array.input(array, :north, [{{0,0}, [4, 5]}])
      iex> result = Clock.run(array, ticks: 2)
      iex> result.tick
      2

  """
  @spec run(ExSystolic.Array.t(), keyword()) :: ExSystolic.Array.t()
  def run(array, opts) do
    backend = Keyword.get(opts, :backend, :interpreted)

    case backend do
      :interpreted ->
        ticks = Keyword.fetch!(opts, :ticks)
        Enum.reduce(1..ticks//1, array, fn _, acc -> step(acc) end)

      :partitioned ->
        Partitioned.run(array, opts)
    end
  end

  @doc """
  Executes a single tick of the array using the interpreted backend.

  Follows the strict order:
  1. INJECT external input streams into boundary link buffers
  2. READ all link buffers
  3. EXECUTE all PEs
  4. COLLECT outputs
  5. WRITE outputs into link buffers
  6. RECORD trace

  ## Examples

      iex> alias ExSystolic.{Array, Clock, PE.MAC}
      iex> array = Array.new(rows: 1, cols: 1) |> Array.fill(MAC) |> Array.connect(:west_to_east) |> Array.connect(:north_to_south)
      iex> array = Array.input(array, :west, [{{0,0}, [3]}])
      iex> array = Array.input(array, :north, [{{0,0}, [4]}])
      iex> result = Clock.step(array)
      iex> result.tick
      1

  """
  @spec step(ExSystolic.Array.t()) :: ExSystolic.Array.t()
  def step(array) do
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

    {new_pes, tick_outputs, events} =
      Interpreted.execute_tick(pes, inputs_map, tick, trace_enabled)

    {new_links, _remaining} =
      Interpreted.write_outputs(drained_links, tick_outputs, %{})

    new_trace =
      if trace_enabled do
        Enum.reduce(events, trace, &Trace.record(&2, &1))
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
end
