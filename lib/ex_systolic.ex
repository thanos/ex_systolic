defmodule ExSystolic do
  @moduledoc """
  A BEAM-native systolic array simulator.

  ex_systolic is a **clocked spatial dataflow simulator**: explicit time
  (ticks), explicit data movement (links), and local processing elements
  (PEs). Data pulses through a grid of simple processors in a regular
  rhythm, like blood through a heart.

  This is not a spreadsheet engine, a DAG executor, or a reactive system.

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
   | `ExSystolic.Grid` | Coordinate geometry and neighbour lookups |
   | `ExSystolic.Space` | Pluggable space / topology behaviour |
   | `ExSystolic.Space.Grid2D` | Default 2D rectangular space implementation |
   | `ExSystolic.Link` | FIFO communication channels between PE ports |
   | `ExSystolic.PE` | Behaviour for processing elements |
   | `ExSystolic.PE.MAC` | Multiply-accumulate PE |
   | `ExSystolic.Array` | Array construction: fill, connect, input |
   | `ExSystolic.Clock` | Tick-by-tick execution driver |
   | `ExSystolic.Trace` | Optional execution trace recording |
   | `ExSystolic.Backend.Interpreted` | Single-process reference backend |
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
