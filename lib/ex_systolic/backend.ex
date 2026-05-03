defmodule ExSystolic.Backend do
  @moduledoc """
  Behaviour for systolic array execution backends.

  A backend implements the tick execution strategy.  All backends must
  produce **identical results** for the same inputs -- this is the
  determinism contract.

  ## Available backends

  | Backend | Module | Strategy |
  |---------|--------|----------|
  | Interpreted | `ExSystolic.Backend.Interpreted` | Single-process, sequential |
  | Partitioned | `ExSystolic.Backend.Partitioned` | Tile-based parallel via `Task.Supervisor` (default) or Poolex |

  ## Tick contract (BSP)

  Every backend must implement the following six steps in order, every
  tick.  Skipping or reordering breaks determinism.

  1. **INJECT** -- push pending external input streams into matching
     boundary link buffers.  Defer when target is full or absent.
  2. **READ** -- drain every link buffer once into a `{coord, port} =>
     value` map.  Missing links yield `:empty`.
  3. **EXECUTE** -- invoke `PE.step/4` for every PE with the read
     inputs.  PEs may execute in parallel **iff** they cannot observe
     each other's writes within the same tick (BSP barrier).
  4. **COLLECT** -- gather all PE outputs into a `coord => outputs`
     map.
  5. **WRITE** -- for each output port that has a matching link
     `from`-endpoint, write the value to that link's buffer.  Drop
     otherwise (e.g. the conventional `:result` port).
  6. **RECORD** -- if tracing is enabled, record one `Trace.Event` per
     PE per tick.  Events must be recorded in deterministic order
     (sorted by `{tick, coord}`).

  Helpers in `ExSystolic.Backend.LinkOps` implement steps 1, 2, and 5
  consistently across backends; you should always use them rather than
  re-implementing the link bookkeeping.

  ## Selecting a backend

      # Default (interpreted)
      Clock.run(array, ticks: 10)

      # Explicit
      Clock.run(array, ticks: 10, backend: :interpreted)
      Clock.run(array, ticks: 10, backend: :partitioned, tile_rows: 4, tile_cols: 4)

      # Partitioned with Poolex pool
      Clock.run(array, ticks: 10, backend: :partitioned, dispatch: :pool)

  ## Implementing a custom backend

  A backend must implement `run/2` which takes an `ExSystolic.Array.t()`
  and a keyword list of options, and returns the final array state.

      defmodule MyBackend do
        @behaviour ExSystolic.Backend

        @impl true
        def run(array, opts) do
          ticks = Keyword.fetch!(opts, :ticks)
          # ... execute ticks following the BSP contract ...
        end
      end

  Run your backend through the conformance suite at
  `ExSystolic.Backend.ConformanceTest` to verify it preserves
  determinism.
  """

  @doc """
  Executes the array for the given number of ticks.

  Must return the final `ExSystolic.Array.t()` with updated PE states,
  links, tick counter, and trace.  The result must be byte-equal across
  invocations with identical inputs (the determinism contract).
  """
  @callback run(ExSystolic.Array.t(), keyword()) :: ExSystolic.Array.t()
end
