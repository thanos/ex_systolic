defmodule ExSystolic do
  @moduledoc """
  A BEAM-native systolic array simulator.

  ex_systolic is a clocked spatial dataflow simulator: explicit time
  (ticks), explicit data movement (links), and local processing elements
  (PEs).  It is NOT a spreadsheet engine, a DAG executor, or a reactive
  system.

  ## Quick start

      alias ExSystolic.{Array, Clock, PE.MAC}

      array =
        Array.new(rows: 2, cols: 2)
        |> Array.fill(MAC)
        |> Array.connect(:west_to_east)
        |> Array.connect(:north_to_south)

      result = Clock.run(array, ticks: 5)

  ## Architecture

  - `ExSystolic.Grid` -- rectangular coordinate geometry
  - `ExSystolic.Link` -- FIFO communication channels between PEs
  - `ExSystolic.PE` -- behaviour for processing elements
  - `ExSystolic.PE.MAC` -- multiply-accumulate PE
  - `ExSystolic.Array` -- array construction and configuration
  - `ExSystolic.Clock` -- tick-by-tick execution driver
  - `ExSystolic.Trace` -- optional execution trace recording
  - `ExSystolic.Backend.Interpreted` -- single-process reference backend
  - `ExSystolic.Examples.GEMM` -- general matrix multiply example
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
