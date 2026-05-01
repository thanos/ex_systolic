defmodule ExSystolic.Grid do
  @moduledoc """
  A rectangular coordinate grid that provides neighbour lookups.

  The grid is the spatial substrate on which processing elements are
  placed.  It knows nothing about PEs or data -- it is pure geometry.

  ## Coordinate system

  - `{row, col}` with row increasing **southward** and col increasing
    **eastward** (standard matrix indexing).
  - Row and column indices start at 0.

  ## Why a separate module?

  Separating geometry from computation keeps the `Array` module focused on
  PE orchestration and makes neighbour logic independently testable.
  """

  @type coord :: {non_neg_integer(), non_neg_integer()}
  @type t :: %__MODULE__{
          rows: pos_integer(),
          cols: pos_integer()
        }

  @enforce_keys [:rows, :cols]
  defstruct [:rows, :cols]

  @doc """
  Creates a rectangular grid of the given dimensions.

  ## Examples

      iex> grid = ExSystolic.Grid.rect(rows: 3, cols: 4)
      iex> grid.rows
      3
      iex> grid.cols
      4

  """
  @spec rect(keyword()) :: t()
  def rect(opts) do
    rows = Keyword.fetch!(opts, :rows)
    cols = Keyword.fetch!(opts, :cols)

    if rows < 1 or cols < 1 do
      raise ArgumentError,
            "rows and cols must be positive, got rows=#{inspect(rows)}, cols=#{inspect(cols)}"
    end

    %__MODULE__{rows: rows, cols: cols}
  end

  @doc """
  Returns the neighbour to the north (row - 1, same col) or `:none`.

  ## Examples

      iex> grid = ExSystolic.Grid.rect(rows: 3, cols: 3)
      iex> ExSystolic.Grid.north(grid, {1, 1})
      {0, 1}
      iex> ExSystolic.Grid.north(grid, {0, 1})
      :none

  """
  @spec north(t(), coord()) :: coord() | :none
  def north(%__MODULE__{rows: _r}, {0, _c}), do: :none
  def north(%__MODULE__{}, {row, col}), do: {row - 1, col}

  @doc """
  Returns the neighbour to the south (row + 1, same col) or `:none`.

  ## Examples

      iex> grid = ExSystolic.Grid.rect(rows: 3, cols: 3)
      iex> ExSystolic.Grid.south(grid, {1, 1})
      {2, 1}
      iex> ExSystolic.Grid.south(grid, {2, 1})
      :none

  """
  @spec south(t(), coord()) :: coord() | :none
  def south(%__MODULE__{rows: r}, {row, _c}) when row >= r - 1, do: :none
  def south(%__MODULE__{}, {row, col}), do: {row + 1, col}

  @doc """
  Returns the neighbour to the east (same row, col + 1) or `:none`.

  ## Examples

      iex> grid = ExSystolic.Grid.rect(rows: 3, cols: 3)
      iex> ExSystolic.Grid.east(grid, {1, 1})
      {1, 2}
      iex> ExSystolic.Grid.east(grid, {1, 2})
      :none

  """
  @spec east(t(), coord()) :: coord() | :none
  def east(%__MODULE__{cols: c}, {_r, col}) when col >= c - 1, do: :none
  def east(%__MODULE__{}, {row, col}), do: {row, col + 1}

  @doc """
  Returns the neighbour to the west (same row, col - 1) or `:none`.

  ## Examples

      iex> grid = ExSystolic.Grid.rect(rows: 3, cols: 3)
      iex> ExSystolic.Grid.west(grid, {1, 1})
      {1, 0}
      iex> ExSystolic.Grid.west(grid, {1, 0})
      :none

  """
  @spec west(t(), coord()) :: coord() | :none
  def west(%__MODULE__{}, {_r, 0}), do: :none
  def west(%__MODULE__{}, {row, col}), do: {row, col - 1}

  @doc """
  Returns all valid coordinates in the grid, row-major order.

  ## Examples

      iex> grid = ExSystolic.Grid.rect(rows: 2, cols: 2)
      iex> ExSystolic.Grid.coords(grid)
      [{0, 0}, {0, 1}, {1, 0}, {1, 1}]

  """
  @spec coords(t()) :: [coord()]
  def coords(%__MODULE__{rows: rows, cols: cols}) do
    for r <- 0..(rows - 1), c <- 0..(cols - 1), do: {r, c}
  end

  @doc """
  Checks whether a coordinate lies inside the grid.

  ## Examples

      iex> grid = ExSystolic.Grid.rect(rows: 2, cols: 2)
      iex> ExSystolic.Grid.member?(grid, {1, 1})
      true
      iex> ExSystolic.Grid.member?(grid, {2, 0})
      false

  """
  @spec member?(t(), coord()) :: boolean()
  def member?(%__MODULE__{rows: rows, cols: cols}, {r, c}) do
    r >= 0 and r < rows and c >= 0 and c < cols
  end
end
