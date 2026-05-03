defmodule ExSystolic.Backend.Interpreted do
  @moduledoc """
  The interpreted (single-BEAM-process) backend for systolic execution.

  This backend runs the entire array in one process, advancing tick by
  tick.  It is the simplest correct implementation and serves as the
  reference semantics for all future backends.

  ## Tick execution order (CRITICAL)

  Each tick executes in this **strict** order, matching the BSP
  contract documented in `ExSystolic.Backend`:

  1. **INJECT** -- push pending external input streams into boundary
     link buffers (handled by `ExSystolic.Clock.step/1`).
  2. **READ**   -- read all link buffers (inputs from previous tick).
  3. **EXECUTE** -- run every PE's `step/4` with those inputs
     (`execute_tick/4`).
  4. **COLLECT** -- gather all PE outputs.
  5. **WRITE**  -- write outputs into link buffers (for next tick).
  6. **RECORD** -- optionally append trace events.

  This ordering guarantees that no PE reads data produced in the same
  tick.  All reads see the state left by the *previous* tick; all writes
  prepare the state for the *next* tick.

  Steps 1, 2, and 5 are delegated to `ExSystolic.Backend.LinkOps`.

  ## Why not GenServer per PE?

  Per-PE GenServers introduce concurrency, non-deterministic scheduling,
  and coordination overhead.  The interpreted backend proves that
  correctness does not require concurrency.  Future backends may add
  parallelism, but the semantics must remain identical.
  """
  alias ExSystolic.Backend.LinkOps
  alias ExSystolic.Link
  alias ExSystolic.Trace

  @doc """
  Executes one tick for all PEs.

  Returns `{new_pes, tick_outputs, trace_events}` where:
  - `new_pes` -- updated PE map with new states
  - `tick_outputs` -- map of coord => outputs map
  - `trace_events` -- list of trace events (empty if tracing disabled)

  ## Examples

      iex> pes = %{{0,0} => {ExSystolic.PE.MAC, 0}}
      iex> inputs_map = %{{{0,0}, :west} => 3, {{0,0}, :north} => 4}
      iex> {new_pes, outputs, _events} = ExSystolic.Backend.Interpreted.execute_tick(pes, inputs_map, 0, true)
      iex> new_pes[{0,0}] |> elem(1)
      12
      iex> outputs[{0,0}].result
      12

  """
  @spec execute_tick(
          %{ExSystolic.Grid.coord() => {module(), ExSystolic.PE.state()}},
          %{{ExSystolic.Grid.coord(), atom()} => term()},
          non_neg_integer(),
          boolean()
        ) ::
          {%{ExSystolic.Grid.coord() => {module(), ExSystolic.PE.state()}},
           %{ExSystolic.Grid.coord() => ExSystolic.PE.outputs()}, [Trace.Event.t()]}
  def execute_tick(pes, inputs_map, tick, trace_enabled) do
    Enum.reduce(pes, {%{}, %{}, []}, fn {coord, {mod, state}}, {acc_pes, acc_outs, acc_evts} ->
      pe_inputs =
        for {{c, port}, val} <- inputs_map, c == coord, into: %{} do
          {port, val}
        end

      context = %{coord: coord}
      {new_state, pe_outputs} = mod.step(state, pe_inputs, tick, context)

      new_events =
        if trace_enabled do
          [
            %Trace.Event{
              tick: tick,
              coord: coord,
              inputs: pe_inputs,
              outputs: pe_outputs,
              state_before: state,
              state_after: new_state
            }
            | acc_evts
          ]
        else
          acc_evts
        end

      {Map.put(acc_pes, coord, {mod, new_state}), Map.put(acc_outs, coord, pe_outputs),
       new_events}
    end)
  end

  @doc """
  Writes PE outputs into link buffers, returning updated links.

  Delegates to `ExSystolic.Backend.LinkOps.write_pe_outputs/2`.  The
  third argument (`input_streams`) is also injected for backwards
  compatibility; the returned tuple includes the remaining (deferred)
  streams.

  Prefer using the split helpers `ExSystolic.Backend.LinkOps.write_pe_outputs/2`
  and `ExSystolic.Backend.LinkOps.inject_streams/2` directly.

  ## Examples

      iex> link = ExSystolic.Link.new({{0,0}, :east}, {{0,1}, :west})
      iex> {new_links, _} = ExSystolic.Backend.Interpreted.write_outputs([link], %{{0,0} => %{east: 5}}, %{})
      iex> ExSystolic.Link.peek(Enum.at(new_links, 0))
      {:ok, 5}

  """
  @spec write_outputs(
          [Link.t()],
          %{ExSystolic.Grid.coord() => ExSystolic.PE.outputs()},
          %{{ExSystolic.Grid.coord(), atom()} => [term()]}
        ) ::
          {[Link.t()], %{{ExSystolic.Grid.coord(), atom()} => [term()]}}
  def write_outputs(links, tick_outputs, input_streams) do
    updated_links = LinkOps.write_pe_outputs(links, tick_outputs)
    LinkOps.inject_streams(updated_links, input_streams)
  end

  @doc """
  Collects final results from the PEs.

  Returns a map of coord => state for all PEs.

  ## Examples

      iex> pes = %{{0,0} => {ExSystolic.PE.MAC, 42}}
      iex> ExSystolic.Backend.Interpreted.collect_results(pes)
      %{{0,0} => 42}

  """
  @spec collect_results(%{ExSystolic.Grid.coord() => {module(), ExSystolic.PE.state()}}) ::
          %{ExSystolic.Grid.coord() => term()}
  def collect_results(pes) do
    for {coord, {_mod, state}} <- pes, into: %{}, do: {coord, state}
  end
end
