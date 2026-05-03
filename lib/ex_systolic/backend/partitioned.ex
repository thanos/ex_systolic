defmodule ExSystolic.Backend.Partitioned do
  @moduledoc """
  A tile-based parallel execution backend.

  The partitioned backend divides the array into rectangular tiles and
  dispatches tile computations in parallel.  Each tick follows the
  Bulk Synchronous Parallel (BSP) model:

  1. **Inject** -- push external input streams into boundary links
  2. **Read** -- read all link buffers (globally, before any PE executes)
  3. **Dispatch** -- submit tile PE computations in parallel
  4. **Collect** -- gather all tile results
  5. **Write** -- write all outputs into link buffers
  6. **Record** -- merge trace events

  ## Dispatch strategies

  Two strategies are available, both deterministic:

  - **`:tasks`** (default) -- uses `Task.Supervisor.async_stream/4`
    against `ExSystolic.TaskSupervisor` with `ordered: true`.  Spawns
    one supervised task per tile per tick.
  - **`:pool`** -- uses the `:systolic_pool` Poolex pool of
    `ExSystolic.Backend.PoolexWorker` GenServers.  Reuses long-lived
    workers, eliminating per-tick task spawn overhead.  Select via
    `dispatch: :pool`.

  ## Determinism guarantee

  Even though tiles execute in parallel within a tick, the BSP barrier
  ensures that all tiles see the same frozen inputs for a given tick.
  No tile reads data produced by another tile in the same tick.  Trace
  events are sorted by `{tick, coord}` before recording so the trace
  list is byte-identical across runs and dispatch strategies.

  ## Options

  - `:ticks` -- number of ticks to run (required)
  - `:tile_rows` -- rows per tile (default: array rows, i.e. single tile)
  - `:tile_cols` -- cols per tile (default: array cols, i.e. single tile)
  - `:dispatch` -- `:tasks` (default) or `:pool`

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
  alias ExSystolic.Backend.{Interpreted, LinkOps}

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
    step_opts = Keyword.take(opts, [:tile_rows, :tile_cols, :dispatch])

    Enum.reduce(1..ticks//1, array, fn _, acc -> step(acc, step_opts) end)
  end

  @doc """
  Executes a single tick using the partitioned backend.

  This is the BSP step: inject, read, dispatch, collect, write, record,
  advance.  Links are managed globally (like the interpreted backend);
  only PE execution is parallelized across tiles.

  ## Examples

      iex> alias ExSystolic.{Array, Backend.Partitioned, PE.MAC}
      iex> array = Array.new(rows: 2, cols: 1) |> Array.fill(MAC) |> Array.connect(:west_to_east)
      iex> array = Array.input(array, :west, [{{0,0}, [10]}, {{1,0}, [20]}])
      iex> array = Partitioned.step(array)
      iex> array.tick
      1

  """
  @spec step(Array.t(), keyword()) :: Array.t()
  def step(array, opts \\ []) do
    %{
      pes: pes,
      links: links,
      tick: tick,
      trace: trace,
      trace_enabled: trace_enabled,
      input_streams: input_streams
    } = array

    dispatch = Keyword.get(opts, :dispatch, :tasks)
    tile_opts = Keyword.take(opts, [:tile_rows, :tile_cols])

    {links_after_inject, remaining_streams} = LinkOps.inject_streams(links, input_streams)

    input_ports =
      links_after_inject
      |> Enum.map(& &1.to)
      |> Enum.uniq()

    {inputs_map, drained_links} = LinkOps.drain_links(links_after_inject, input_ports)

    tiles = TilePartitioner.partition(%{array | pes: pes}, tile_opts)

    tile_results = dispatch_tiles(tiles, inputs_map, tick, trace_enabled, dispatch)

    {new_pes, tick_outputs, all_events} = collect_results(tile_results, pes)

    new_links = LinkOps.write_pe_outputs(drained_links, tick_outputs)

    new_trace =
      if trace_enabled do
        all_events
        |> Enum.sort_by(&{&1.tick, &1.coord})
        |> Enum.reduce(trace, &Trace.record(&2, &1))
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

  defp dispatch_tiles(tiles, inputs_map, tick, trace_enabled, :tasks) do
    # `ordered: true` keeps results in the same order as `tiles`, ensuring
    # the trace event list is reproducible across runs even though execution
    # is parallel. `Task.Supervisor.async_stream/4` ties spawned tasks to
    # the application's supervision tree so they cannot leak on doctest
    # failure or process exit.
    ExSystolic.TaskSupervisor
    |> Task.Supervisor.async_stream(
      tiles,
      fn tile -> Interpreted.execute_tick(tile.pes, inputs_map, tick, trace_enabled) end,
      max_concurrency: System.schedulers_online(),
      ordered: true,
      timeout: :infinity
    )
    |> Enum.zip(tiles)
    |> Enum.map(fn {{:ok, result}, tile} -> {tile, result} end)
  end

  defp dispatch_tiles(tiles, inputs_map, tick, trace_enabled, :pool) do
    for tile <- tiles do
      {tile, pool_dispatch_tile(tile.pes, inputs_map, tick, trace_enabled)}
    end
  end

  defp dispatch_tiles(_tiles, _inputs_map, _tick, _trace_enabled, other) do
    raise ArgumentError,
          "unknown dispatch strategy #{inspect(other)}; expected :tasks or :pool"
  end

  defp pool_dispatch_tile(pes, inputs_map, tick, trace_enabled) do
    case Poolex.run(
           :systolic_pool,
           fn worker ->
             GenServer.call(
               worker,
               {:run_tile, pes, inputs_map, tick, trace_enabled},
               :infinity
             )
           end,
           checkout_timeout: :infinity
         ) do
      {:ok, result} ->
        result

      {:error, reason} ->
        raise "Poolex dispatch failed: #{inspect(reason)}"
    end
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
