defmodule ExSystolic do
  @moduledoc """
  A BEAM-native systolic array simulator.

  ex_systolic is a **clocked spatial dataflow simulator**: explicit time
  (ticks), explicit data movement (links), and local processing elements
  (PEs). Data pulses through a grid of simple processors in a regular
  rhythm, like blood through a heart.

  This is not a spreadsheet engine, a DAG executor, or a reactive system.

  ## Architecture

  Every tick follows the Bulk Synchronous Parallel (BSP) model:

      ┌─────────┐  INJECT   ┌─────────┐  READ    ┌─────────┐  EXECUTE
      │  Input  │──────────>│  Links   │─────────>│   PEs   │──────────┐
      │ Streams │           │ (FIFOs)  │          │ (step)  │          │
      └─────────┘          └─────────┘          └─────────┘          │
                                                                    │ COLLECT
                                                                    ▼
      ┌─────────┐  RECORD   ┌─────────┐  WRITE   ┌─────────┐  ┌─────────┐
      │  Trace  │<──────────│  Clock  │<─────────│  Links  │  │Outputs  │
      │ Events  │           │ driver  │          │ (FIFOs) │  │  map    │
      └─────────┘           └─────────┘          └─────────┘  └─────────┘

  All backends (interpreted, partitioned) execute the same six-step
  sequence.  The partitioned backend parallelises step 3 (EXECUTE)
  across tiles but preserves determinism via the BSP barrier.

  ## Tutorial & Examples

  The full tutorial, quick-start guide, real-world examples (image
  convolution, shortest paths), architecture diagrams, roadmap, and
  references are in the [README](readme.html).

  ## One-minute quick start

      alias ExSystolic.{Array, Clock, PE.MAC}

      array =
        Array.new(rows: 2, cols: 2)
        |> Array.fill(MAC)
        |> Array.connect(:west_to_east)
        |> Array.connect(:north_to_south)
        |> Array.input(:west, [{{0, 0}, [1, 2]}, {{1, 0}, [3, 4]}])
        |> Array.input(:north, [{{0, 0}, [5, 7]}, {{0, 1}, [6, 8]}])

      result = Clock.run(array, ticks: 5)

  ## Module overview

  | Module | Role |
  |--------|------|
  | `ExSystolic` | Top-level entry point and version |
  | `ExSystolic.Application` | Supervision tree (TaskSupervisor, Poolex pool) |
  | `ExSystolic.Grid` | Coordinate geometry and neighbour lookups |
  | `ExSystolic.Space` | Pluggable space / topology behaviour |
  | `ExSystolic.Space.Grid2D` | Default 2D rectangular space implementation |
  | `ExSystolic.Link` | FIFO communication channels between PE ports |
  | `ExSystolic.PE` | Behaviour for processing elements; `value/2`, `present?/2` helpers |
  | `ExSystolic.PE.MAC` | Multiply-accumulate PE |
  | `ExSystolic.Array` | Array construction: fill, connect, input, results |
  | `ExSystolic.Clock` | Tick-by-tick execution driver |
  | `ExSystolic.Trace` | Execution trace recording and querying |
  | `ExSystolic.Backend` | Backend behaviour and BSP contract |
  | `ExSystolic.Backend.LinkOps` | Shared link buffer operations (inject, drain, write) |
  | `ExSystolic.Backend.Interpreted` | Single-process reference backend |
  | `ExSystolic.Backend.Partitioned` | Tile-based parallel backend (Task.Supervisor or Poolex) |
  | `ExSystolic.Backend.PoolexWorker` | GenServer worker for Poolex dispatch |
  | `ExSystolic.Tile` | Tile data structure for partitioned execution |
  | `ExSystolic.TilePartitioner` | Splits array into rectangular tiles |
  | `ExSystolic.Examples.GEMM` | General matrix multiply |
  """

  @doc """
  Returns the version of ex_systolic.

  ## Examples

      iex> is_binary(ExSystolic.version())
      true

  """
  @spec version() :: String.t()
  def version do
    Application.spec(:ex_systolic, :vsn) |> to_string()
  end
end
