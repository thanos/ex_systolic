defmodule ExSystolic.PE.MAC do
  @moduledoc """
  Multiply-Accumulate processing element -- the classic systolic PE.

  ## Ports

      inputs:  west => a, north => b
      outputs: east => a, south => b, result => acc

  The MAC PE receives a value from its west neighbour and a value from
  its north neighbour, multiplies them, adds the product to an
  accumulator, and forwards both input values unchanged to the east and
  south respectively.

  This is the exact PE used in the canonical systolic GEMM algorithm
  (Kung & Leiserson, 1979).  Data flows west-to-east on the horizontal
  axis and north-to-south on the vertical axis; partial sums accumulate
  in-place at each PE.

  ## State

  The PE state is simply the accumulator value, defaulting to 0.

  ## GraphBLAS connection

  The MAC PE computes one entry of the semi-ring product C = A * B
  where the semi-ring is `(multiply: *, add: +)` over real numbers.
  GraphBLAS defines the same computation over arbitrary semi-rings.
  """

  @behaviour ExSystolic.PE

  @type state :: number()

  @doc """
  Initializes the MAC PE with an optional initial accumulator.

  ## Examples

      iex> ExSystolic.PE.MAC.init([])
      0

      iex> ExSystolic.PE.MAC.init(acc: 10)
      10

  """
  @impl true
  @spec init(keyword()) :: state()
  def init(opts \\ []) do
    Keyword.get(opts, :acc, 0)
  end

  @doc """
  Executes one MAC step: acc = acc + a * b; forwards a east and b south.

  When an input port is absent from the inputs map or has the value
  `:empty`, it is treated as zero for accumulation and is NOT forwarded.
  An explicit zero value (0) IS forwarded.

  ## Examples

      iex> {state, outputs} = ExSystolic.PE.MAC.step(0, %{west: 3, north: 4}, 0, %{})
      iex> state
      12
      iex> outputs.east
      3
      iex> outputs.south
      4
      iex> outputs.result
      12

      iex> {state2, outputs2} = ExSystolic.PE.MAC.step(12, %{west: 2, north: 5}, 1, %{})
      iex> state2
      22
      iex> outputs2.result
      22

  """
  @impl true
  @spec step(state(), ExSystolic.PE.inputs(), non_neg_integer(), ExSystolic.PE.context()) ::
          {state(), ExSystolic.PE.outputs()}
  def step(acc, inputs, _tick, _context) do
    a = Map.get(inputs, :west)
    b = Map.get(inputs, :north)

    a_val = ExSystolic.PE.value(a, 0)
    b_val = ExSystolic.PE.value(b, 0)

    new_acc = acc + a_val * b_val

    outputs = %{result: new_acc}
    outputs = if ExSystolic.PE.present?(a), do: Map.put(outputs, :east, a), else: outputs
    outputs = if ExSystolic.PE.present?(b), do: Map.put(outputs, :south, b), else: outputs

    {new_acc, outputs}
  end
end
