defmodule ExSystolic.Examples.GEMM do
  @moduledoc """
  General Matrix Multiply (GEMM) using a systolic wavefront.

  Given two matrices A (m x k) and B (k x n), computes C = A * B
  where C is (m x n) using a systolic array of MAC processing elements.

  ## Systolic wavefront algorithm

  The key insight: in a systolic GEMM, elements of A flow **east** and
  elements of B flow **south**.  Each PE at position (i, j) accumulates
  the dot product of row i of A and column j of B.

  The input streams must be **skewed** so that data arrives at each PE
  at the right tick:

  - Row i of A is delayed by i ticks (padded with leading zeros).
  - Column j of B is delayed by j ticks (padded with leading zeros).

  After k + m + n - 1 ticks, every PE has accumulated its final result.

  ## GraphBLAS connection

  Matrix multiplication over the arithmetic semi-ring `(multiply: *,
  add: +)` is the foundational operation in GraphBLAS.  The same
  structure works over arbitrary semi-rings (e.g. boolean, tropical).

  ## Examples

      iex> A = [[1, 2], [3, 4]]
      iex> B = [[5, 6], [7, 8]]
      iex> ExSystolic.Examples.GEMM.run(A, B)
      [[19, 22], [43, 50]]

      iex> A = [[2, 0, 1], [3, 1, 2]]
      iex> B = [[1, 2], [0, 3], [4, 1]]
      iex> ExSystolic.Examples.GEMM.run(A, B)
      [[6, 5], [11, 11]]

  """

  alias ExSystolic.{Array, Clock, PE.MAC}

  @doc """
  Runs GEMM: computes C = A * B using a systolic array.

  A is an m x k matrix, B is a k x n matrix.  Returns C as a list of
  lists (m x n).

  ## Examples

      iex> ExSystolic.Examples.GEMM.run([[1]], [[1]])
      [[1]]

  """
  @spec run([[number()]], [[number()]]) :: [[number()]]
  def run(a, b) do
    m = length(a)
    k = length(hd(a))
    n = length(hd(b))

    array =
      Array.new(rows: m, cols: n)
      |> Array.fill(MAC)
      |> Array.connect(:west_to_east)
      |> Array.connect(:north_to_south)
      |> Array.input(:west, west_streams(a, m, k, n))
      |> Array.input(:north, north_streams(b, m, k, n))

    ticks_needed = k + m + n - 1
    result = Clock.run(array, ticks: ticks_needed)

    Array.result_matrix(result)
  end

  @doc """
  Generates the skewed west input streams from matrix A.

  Row i of A enters the array at PE (i, 0) on the west boundary.
  It is delayed by i leading zeros.  After the data, trailing zeros
  pad the stream so that every tick has a value.  The trailing zeros
  do not affect the accumulator because 0 * x = 0.

  Each stream targets the boundary link at `{r, 0}` port `:west`.

  ## Examples

      iex> streams = ExSystolic.Examples.GEMM.west_streams([[1,2],[3,4]], 2, 2, 2)
      iex> {_, row0} = Enum.find(streams, fn {{r,_},_} -> r == 0 end)
      iex> {_, row1} = Enum.find(streams, fn {{r,_},_} -> r == 1 end)
      iex> row0
      [1, 2, 0, 0, 0]
      iex> row1
      [0, 3, 4, 0, 0]

  """
  @spec west_streams([[number()]], pos_integer(), pos_integer(), pos_integer()) ::
          [{{non_neg_integer(), non_neg_integer()}, [number()]}]
  def west_streams(a, m, k, n) do
    total = k + m + n - 1

    for i <- 0..(m - 1) do
      row = Enum.at(a, i)
      leading = List.duplicate(0, i)
      data_count = i + k
      trailing = List.duplicate(0, total - data_count)
      {{i, 0}, leading ++ row ++ trailing}
    end
  end

  @doc """
  Generates the skewed north input streams from matrix B.

  Column j of B enters the array at PE (0, j) on the north boundary.
  It is delayed by j leading zeros.

  Each stream targets the boundary link at `{0, c}` port `:north`.

  ## Examples

      iex> streams = ExSystolic.Examples.GEMM.north_streams([[5,6],[7,8]], 2, 2, 2)
      iex> {_, col0} = Enum.find(streams, fn {{_,c},_} -> c == 0 end)
      iex> {_, col1} = Enum.find(streams, fn {{_,c},_} -> c == 1 end)
      iex> col0
      [5, 7, 0, 0, 0]
      iex> col1
      [0, 6, 8, 0, 0]

  """
  @spec north_streams([[number()]], pos_integer(), pos_integer(), pos_integer()) ::
          [{{non_neg_integer(), non_neg_integer()}, [number()]}]
  def north_streams(b, m, k, n) do
    total = k + m + n - 1

    for j <- 0..(n - 1) do
      col = for i <- 0..(k - 1), do: Enum.at(Enum.at(b, i), j)
      leading = List.duplicate(0, j)
      data_count = j + k
      trailing = List.duplicate(0, total - data_count)
      {{0, j}, leading ++ col ++ trailing}
    end
  end
end
