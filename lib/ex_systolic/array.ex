defmodule ExSystolic.Array do
  @moduledoc """
  A systolic array: a grid of processing elements connected by links.

  The Array module provides the user-facing API for building and running
  systolic computations.  It composes Space, Link, PE, and Clock into a
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

  ## Pluggable space

  By default, arrays use `ExSystolic.Space.Grid2D` as their spatial
  model.  You can supply a custom space module:

      Array.new(space: {MySpace, key: value})

  The space module must implement `ExSystolic.Space`.

  ## Data structure

  The array is a plain map with these keys:

  - `:space`     -- `{module, opts}` tuple defining the spatial model
  - `:grid`      -- the coordinate grid (backward compat, derived from space)
  - `:pes`       -- map of coord => {module, state}
  - `:links`     -- list of Link structs
  - `:tick`      -- current tick counter
  - `:trace`     -- trace data
  - `:trace_enabled` -- whether tracing is active
  - `:input_streams` -- pending external input streams
  """

  alias ExSystolic.{Grid, Link, Space.Grid2D, Trace}

  @type space_spec :: {module(), keyword()}

  defstruct space: nil,
            grid: nil,
            pes: %{},
            links: [],
            tick: 0,
            trace: Trace.new(),
            trace_enabled: false,
            input_streams: %{}

  @type t :: %__MODULE__{
          space: space_spec(),
          grid: Grid.t(),
          pes: %{Grid.coord() => {module(), ExSystolic.PE.state()}},
          links: [Link.t()],
          tick: non_neg_integer(),
          trace: Trace.t(),
          trace_enabled: boolean(),
          input_streams: %{{Grid.coord(), atom()} => [term()]}
        }

  @doc """
  Creates a new empty array.

  Accepts either `rows:` / `cols:` (backward compatible) or `space:`
  for a custom spatial model.

  ## Examples

      iex> array = ExSystolic.Array.new(rows: 2, cols: 3)
      iex> array.grid.rows
      2
      iex> array.tick
      0
      iex> elem(array.space, 0)
      ExSystolic.Space.Grid2D

      iex> array = ExSystolic.Array.new(space: {ExSystolic.Space.Grid2D, rows: 2, cols: 3})
      iex> array.grid.rows
      2

  """
  @spec new(keyword()) :: t()
  def new(opts) do
    {space_mod, space_opts} = resolve_space(opts)
    grid_opts = extract_grid_opts(space_mod, space_opts, opts)

    grid =
      Grid.rect(rows: Keyword.fetch!(grid_opts, :rows), cols: Keyword.fetch!(grid_opts, :cols))

    %__MODULE__{
      space: {space_mod, space_opts},
      grid: grid,
      pes: %{},
      links: [],
      tick: 0,
      trace: Trace.new(),
      trace_enabled: false,
      input_streams: %{}
    }
  end

  defp resolve_space(opts) do
    case Keyword.get(opts, :space) do
      nil ->
        rows = Keyword.fetch!(opts, :rows)
        cols = Keyword.fetch!(opts, :cols)
        {Grid2D, [rows: rows, cols: cols]}

      {mod, space_opts} ->
        {mod, space_opts}
    end
  end

  defp extract_grid_opts(Grid2D, space_opts, _opts), do: space_opts

  defp extract_grid_opts(_mod, space_opts, opts) do
    case Keyword.take(opts, [:rows, :cols]) do
      [] -> space_opts
      grid_opts -> grid_opts
    end
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

  Uses the array's Space module to determine neighbour relationships
  and materializes links accordingly.  For Grid2D, this produces the
  same links as before.

  Supported directions:

  - `:west_to_east` -- links flowing eastward (row r, col c -> col c+1)
  - `:north_to_south` -- links flowing southward (row r, col c -> row r+1)

  Boundary links for external input are also created.

  ## Examples

      iex> array = ExSystolic.Array.new(rows: 2, cols: 2) |> ExSystolic.Array.fill(ExSystolic.PE.MAC)
      iex> array = ExSystolic.Array.connect(array, :west_to_east)
      iex> length(array.links)
      4

  """
  @spec connect(t(), :west_to_east | :north_to_south) :: t()
  def connect(%{space: {space_mod, space_opts}, links: links} = array, direction) do
    new_links = build_direction_links(space_mod, space_opts, direction)
    %{array | links: links ++ new_links}
  end

  defp build_direction_links(Grid2D, space_opts, :west_to_east) do
    boundary = west_boundary_links(space_opts)
    internal = west_east_internal_links(space_opts)
    boundary ++ internal
  end

  defp build_direction_links(Grid2D, space_opts, :north_to_south) do
    boundary = north_boundary_links(space_opts)
    internal = north_south_internal_links(space_opts)
    boundary ++ internal
  end

  defp build_direction_links(space_mod, space_opts, direction) do
    materialize_links_from_space(space_mod, space_opts, direction)
  end

  defp west_boundary_links(opts) do
    rows = Keyword.fetch!(opts, :rows)

    for r <- 0..(rows - 1) do
      Link.new({{r, -1}, :east}, {{r, 0}, :west})
    end
  end

  defp west_east_internal_links(opts) do
    rows = Keyword.fetch!(opts, :rows)
    cols = Keyword.fetch!(opts, :cols)

    if cols > 1 do
      for r <- 0..(rows - 1),
          c <- 0..(cols - 2) do
        Link.new({{r, c}, :east}, {{r, c + 1}, :west})
      end
    else
      []
    end
  end

  defp north_boundary_links(opts) do
    cols = Keyword.fetch!(opts, :cols)

    for c <- 0..(cols - 1) do
      Link.new({{-1, c}, :south}, {{0, c}, :north})
    end
  end

  defp north_south_internal_links(opts) do
    rows = Keyword.fetch!(opts, :rows)
    cols = Keyword.fetch!(opts, :cols)

    if rows > 1 do
      for r <- 0..(rows - 2),
          c <- 0..(cols - 1) do
        Link.new({{r, c}, :south}, {{r + 1, c}, :north})
      end
    else
      []
    end
  end

  defp materialize_links_from_space(space_mod, space_opts, direction) do
    coords = space_mod.coords(space_opts)
    {from_port, to_port} = direction_ports(direction)

    internal =
      for coord <- coords,
          neighbors = space_mod.neighbors(coord, space_opts),
          neighbor = Map.get(neighbors, from_port),
          neighbor != nil do
        Link.new({coord, from_port}, {neighbor, to_port})
      end

    boundary =
      for coord <- coords,
          neighbors = space_mod.neighbors(coord, space_opts),
          Map.get(neighbors, from_port) == nil do
        boundary_from = boundary_from(coord, from_port)
        Link.new(boundary_from, {coord, to_port})
      end

    boundary ++ internal
  end

  defp direction_ports(:west_to_east), do: {:east, :west}
  defp direction_ports(:north_to_south), do: {:south, :north}

  defp boundary_from({r, _c}, :east), do: {{r, -1}, :east}
  defp boundary_from({_r, c}, :south), do: {{-1, c}, :south}

  @doc """
  Materializes all links for the array using its Space module.

  Creates links for every neighbour relationship returned by the space.
  This is an alternative to calling `connect/2` for each direction
  individually -- useful for custom spaces where directions are not
  known in advance.

  ## Examples

      iex> array = ExSystolic.Array.new(rows: 2, cols: 2) |> ExSystolic.Array.fill(ExSystolic.PE.MAC)
      iex> array = ExSystolic.Array.materialize_links(array)
      iex> length(array.links)
      8

  """
  @spec materialize_links(t()) :: t()
  def materialize_links(%{space: {space_mod, space_opts}, links: links} = array) do
    coords = space_mod.coords(space_opts)

    new_links =
      for coord <- coords,
          neighbors = space_mod.neighbors(coord, space_opts),
          {port, neighbor} <- neighbors,
          neighbor != nil do
        to_port = peer_port(port)
        Link.new({coord, port}, {neighbor, to_port})
      end

    %{array | links: links ++ new_links}
  end

  defp peer_port(:east), do: :west
  defp peer_port(:west), do: :east
  defp peer_port(:north), do: :south
  defp peer_port(:south), do: :north

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
        cell_state(pes, {r, c})
      end
    end
  end

  defp cell_state(pes, coord) do
    case Map.get(pes, coord) do
      {_mod, state} -> state
      nil -> nil
    end
  end
end
