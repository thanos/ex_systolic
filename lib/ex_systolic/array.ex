defmodule ExSystolic.Array do
  @moduledoc """
  A systolic array: a grid of processing elements connected by links.

  The Array module provides the user-facing API for building and running
  systolic computations.  It composes Grid, Link, PE, and Clock into a
  single coherent data structure.

  ## Construction

      array =
        Array.new(rows: 3, cols: 3)
        |> Array.fill(MyPE)
        |> Array.connect(:west_to_east)
        |> Array.connect(:north_to_south)
        |> Array.input(:west, [{{0,0}, [1,2,3]}, {{1,0}, [4,5,6]}])
        |> Array.input(:north, [{{0,0}, [7,8]}, {{0,1}, [9,10]}])

  ## Execution

      result = Clock.run(array, ticks: 10)

  ## Data structure

  The array is a plain map with these keys:

  - `:grid`    -- the coordinate grid
  - `:pes`     -- map of coord => {module, state}
  - `:links`   -- list of Link structs
  - `:tick`    -- current tick counter
  - `:trace`   -- trace data
  - `:trace_enabled` -- whether tracing is active
  - `:input_streams` -- pending external input streams
  """

  alias ExSystolic.{Grid, Link, Trace}

  @type t :: %{
          grid: Grid.t(),
          pes: %{Grid.coord() => {module(), ExSystolic.PE.state()}},
          links: [Link.t()],
          tick: non_neg_integer(),
          trace: %{events: [Trace.Event.t()]},
          trace_enabled: boolean(),
          input_streams: %{{Grid.coord(), atom()} => [term()]}
        }

  @doc """
  Creates a new empty array with the given dimensions.

  The array has no PEs, no links, tick 0, and tracing disabled.

  ## Examples

      iex> array = ExSystolic.Array.new(rows: 2, cols: 3)
      iex> array.grid.rows
      2
      iex> array.tick
      0

  """
  @spec new(keyword()) :: t()
  def new(opts) do
    grid = Grid.rect(rows: Keyword.fetch!(opts, :rows), cols: Keyword.fetch!(opts, :cols))

    %{
      grid: grid,
      pes: %{},
      links: [],
      tick: 0,
      trace: Trace.new(),
      trace_enabled: false,
      input_streams: %{}
    }
  end

  @doc """
  Fills every grid position with the given PE module.

  Each PE is initialized via its `init/1` callback with an empty option
  list.  The default accumulator for MAC is 0.

  ## Examples

      iex> array = ExSystolic.Array.new(rows: 2, cols: 2) |> ExSystolic.Array.fill(ExSystolic.PE.MAC)
      iex> map_size(array.pes)
      4
      iex> elem(array.pes[{0,0}], 0)
      ExSystolic.PE.MAC

  """
  @spec fill(t(), module()) :: t()
  def fill(%{grid: grid, pes: pes} = array, pe_module) do
    new_pes =
      for coord <- Grid.coords(grid), into: pes do
        {coord, {pe_module, pe_module.init([])}}
      end

    %{array | pes: new_pes}
  end

  @doc """
  Fills every grid position with the given PE module and per-PE options.

  `pe_opts` is a map of coord => keyword().  PEs not in the map get
  default init options `[]`.

  ## Examples

      iex> array = ExSystolic.Array.new(rows: 1, cols: 1)
      iex> array = ExSystolic.Array.fill(array, ExSystolic.PE.MAC, %{{0,0} => [acc: 100]})
      iex> elem(array.pes[{0,0}], 1)
      100

  """
  @spec fill(t(), module(), %{Grid.coord() => keyword()}) :: t()
  def fill(%{grid: grid, pes: pes} = array, pe_module, pe_opts) do
    new_pes =
      for coord <- Grid.coords(grid), into: pes do
        opts = Map.get(pe_opts, coord, [])
        {coord, {pe_module, pe_module.init(opts)}}
      end

    %{array | pes: new_pes}
  end

  @doc """
  Connects PEs along the specified axis.

  Supported directions:

  - `:west_to_east` -- for each row, link col c's `:east` output to
    col c+1's `:west` input.
  - `:north_to_south` -- for each column, link row r's `:south` output
    to row r+1's `:north` input.

  Also creates boundary links for external input:
  - `:west_to_east` creates links from virtual boundary coords `{-1, c}`
    with port `:east` to `{0, c}` with port `:west`.
  - `:north_to_south` creates links from virtual boundary coords `{r, -1}`
    with port `:south` to `{r, 0}` with port `:north`.

  ## Examples

      iex> array = ExSystolic.Array.new(rows: 2, cols: 2) |> ExSystolic.Array.fill(ExSystolic.PE.MAC)
      iex> array = ExSystolic.Array.connect(array, :west_to_east)
      iex> length(array.links)
      4

  """
  @spec connect(t(), :west_to_east | :north_to_south) :: t()
  def connect(%{grid: grid, links: links} = array, direction) do
    new_links = build_direction_links(grid, direction)
    %{array | links: links ++ new_links}
  end

  defp build_direction_links(grid, :west_to_east) do
    boundary = west_boundary_links(grid)
    internal = west_east_internal_links(grid)
    boundary ++ internal
  end

  defp build_direction_links(grid, :north_to_south) do
    boundary = north_boundary_links(grid)
    internal = north_south_internal_links(grid)
    boundary ++ internal
  end

  defp west_boundary_links(grid) do
    for r <- 0..(grid.rows - 1) do
      Link.new({{-1, r}, :east}, {{r, 0}, :west})
    end
  end

  defp west_east_internal_links(grid) when grid.cols > 1 do
    for r <- 0..(grid.rows - 1),
        c <- 0..(grid.cols - 2) do
      Link.new({{r, c}, :east}, {{r, c + 1}, :west})
    end
  end

  defp west_east_internal_links(_grid), do: []

  defp north_boundary_links(grid) do
    for c <- 0..(grid.cols - 1) do
      Link.new({{c, -1}, :south}, {{0, c}, :north})
    end
  end

  defp north_south_internal_links(grid) when grid.rows > 1 do
    for r <- 0..(grid.rows - 2),
        c <- 0..(grid.cols - 1) do
      Link.new({{r, c}, :south}, {{r + 1, c}, :north})
    end
  end

  defp north_south_internal_links(_grid), do: []

  @doc """
  Attaches external input streams to the array.

  `direction` is `:west` or `:north`, indicating which boundary the
  streams enter from.

  `stream_specs` is a list of `{{row, col}, values}` where `values` is
  a list of items to inject one per tick into the PE at `{row, col}`
  through the appropriate port.

  For `:west`, items enter at port `:west`.
  For `:north`, items enter at port `:north`.

  ## Examples

      iex> array = ExSystolic.Array.new(rows: 2, cols: 2) |> ExSystolic.Array.fill(ExSystolic.PE.MAC)
      iex> array = ExSystolic.Array.connect(array, :west_to_east)
      iex> array = ExSystolic.Array.connect(array, :north_to_south)
      iex> array = ExSystolic.Array.input(array, :west, [{{0,0}, [1,2,3]}])
      iex> map_size(array.input_streams)
      1

  """
  @spec input(t(), :west | :north, [{{non_neg_integer(), non_neg_integer()}, [term()]}]) :: t()
  def input(%{input_streams: streams} = array, direction, stream_specs) do
    port =
      case direction do
        :west -> :west
        :north -> :north
      end

    new_streams =
      for {{row, col}, values} <- stream_specs, reduce: streams do
        acc -> Map.put(acc, {{row, col}, port}, values)
      end

    %{array | input_streams: new_streams}
  end

  @doc """
  Enables trace recording on the array.

  ## Examples

      iex> array = ExSystolic.Array.new(rows: 1, cols: 1) |> ExSystolic.Array.trace(true)
      iex> array.trace_enabled
      true

  """
  @spec trace(t(), boolean()) :: t()
  def trace(array, enabled), do: %{array | trace_enabled: enabled}

  @doc """
  Extracts the result matrix from the array's PE states.

  Returns a list of lists (row-major) suitable for matrix operations.
  Each entry is the PE state at that coordinate.

  ## Examples

      iex> array = ExSystolic.Array.new(rows: 2, cols: 2) |> ExSystolic.Array.fill(ExSystolic.PE.MAC)
      iex> ExSystolic.Array.result_matrix(array)
      [[0, 0], [0, 0]]

  """
  @spec result_matrix(t()) :: [[term()]]
  def result_matrix(%{grid: grid, pes: pes}) do
    for r <- 0..(grid.rows - 1) do
      for c <- 0..(grid.cols - 1) do
        {_mod, state} = pes[{r, c}]
        state
      end
    end
  end
end
