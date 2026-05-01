defmodule ExSystolic.Space.Grid2D do
  @moduledoc """
  A 2D rectangular grid implementation of the Space behaviour.

  This is the default space for systolic arrays.  It provides the same
  coordinate semantics as `ExSystolic.Grid` but through the `Space`
  behaviour interface, making it interchangeable with future space
  implementations (graph, hierarchical, etc.).

  ## Coordinate system

  - `{row, col}` with row increasing southward, col increasing eastward.
  - Indices start at 0.

  ## Port layout

  Every PE in a Grid2D has four directional ports: `:north`, `:south`,
  `:east`, `:west`.  Boundary PEs have `nil` neighbours on their
  outward-facing ports.

  ## Relationship to ExSystolic.Grid

  `Grid2D` and `Grid` share the same coordinate semantics.  `Grid`
  remains available for direct use; `Grid2D` adds the Space behaviour
  layer that enables pluggable topology.
  """

  @behaviour ExSystolic.Space

  @type coord :: {non_neg_integer(), non_neg_integer()}

  @doc """
  Validates and normalizes a coordinate.

  Accepts `{row, col}` tuples where both are non-negative integers.

  ## Examples

      iex> ExSystolic.Space.Grid2D.normalize({1, 2})
      {:ok, {1, 2}}

      iex> ExSystolic.Space.Grid2D.normalize({-1, 0})
      {:error, :invalid_coordinate}

      iex> ExSystolic.Space.Grid2D.normalize("not_a_coord")
      {:error, :invalid_coordinate}

  """
  @impl true
  @spec normalize(term()) :: {:ok, coord()} | {:error, term()}
  def normalize({r, c}) when is_integer(r) and r >= 0 and is_integer(c) and c >= 0,
    do: {:ok, {r, c}}

  def normalize(_), do: {:error, :invalid_coordinate}

  @doc """
  Returns the neighbours of a coordinate within a grid of the given size.

  Boundary positions return `nil` for out-of-bounds neighbours.

  Coordinate system: `{row, col}` with row increasing southward and
  col increasing eastward.  This matches `ExSystolic.Grid`.

  ## Examples

      iex> ExSystolic.Space.Grid2D.neighbors({1, 1}, rows: 3, cols: 3)
      %{north: {0, 1}, south: {2, 1}, east: {1, 2}, west: {1, 0}}

      iex> ExSystolic.Space.Grid2D.neighbors({0, 0}, rows: 3, cols: 3)
      %{north: nil, south: {1, 0}, east: {0, 1}, west: nil}

      iex> ExSystolic.Space.Grid2D.neighbors({2, 2}, rows: 3, cols: 3)
      %{north: {1, 2}, south: nil, east: nil, west: {2, 1}}

  """
  @impl true
  @spec neighbors(coord(), keyword()) :: %{optional(atom()) => coord() | nil}
  def neighbors({row, col}, opts) do
    rows = Keyword.fetch!(opts, :rows)
    cols = Keyword.fetch!(opts, :cols)

    %{
      north: if(row - 1 >= 0, do: {row - 1, col}, else: nil),
      south: if(row + 1 < rows, do: {row + 1, col}, else: nil),
      east: if(col + 1 < cols, do: {row, col + 1}, else: nil),
      west: if(col - 1 >= 0, do: {row, col - 1}, else: nil)
    }
  end

  @doc """
  Returns the port names for a Grid2D coordinate.

  Always returns `[:north, :south, :east, :west]` regardless of
  position (boundary PEs still have the ports; they simply have no
  neighbour connected on those ports).

  ## Examples

      iex> ExSystolic.Space.Grid2D.ports({0, 0}, rows: 2, cols: 2)
      [:north, :south, :east, :west]

  """
  @impl true
  @spec ports(coord(), keyword()) :: [atom()]
  def ports(_coord, _opts), do: [:north, :south, :east, :west]

  @doc """
  Returns all valid coordinates in the grid, row-major order.

  ## Examples

      iex> ExSystolic.Space.Grid2D.coords(rows: 2, cols: 2)
      [{0, 0}, {0, 1}, {1, 0}, {1, 1}]

  """
  @spec coords(keyword()) :: [coord()]
  def coords(opts) do
    rows = Keyword.fetch!(opts, :rows)
    cols = Keyword.fetch!(opts, :cols)
    for r <- 0..(rows - 1), c <- 0..(cols - 1), do: {r, c}
  end
end
