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
  | Partitioned | `ExSystolic.Backend.Partitioned` | Tile-based parallel via Poolex |

  ## Selecting a backend

      # Default (interpreted)
      Clock.run(array, ticks: 10)

      # Explicit
      Clock.run(array, ticks: 10, backend: :interpreted)
      Clock.run(array, ticks: 10, backend: :partitioned, tile_rows: 4, tile_cols: 4)

  ## Implementing a custom backend

  A backend must implement `run/2` which takes an `ExSystolic.Array.t()`
  and a keyword list of options, and returns the final array state.

      defmodule MyBackend do
        @behaviour ExSystolic.Backend

        @impl true
        def run(array, opts) do
          ticks = Keyword.fetch!(opts, :ticks)
          # ... execute ticks ...
        end
      end
  """

  @doc """
  Executes the array for the given number of ticks.

  Must return the final `ExSystolic.Array.t()` with updated PE states,
  links, tick counter, and trace.
  """
  @callback run(ExSystolic.Array.t(), keyword()) :: ExSystolic.Array.t()
end
