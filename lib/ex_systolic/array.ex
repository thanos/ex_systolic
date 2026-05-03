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

   The array is an `%ExSystolic.Array{}` struct with these fields:

   - `:space`     -- `{module, opts}` tuple defining the spatial model
   - `:grid`      -- the coordinate grid (backward compat, derived from space)
   - `:pes`       -- map of coord => {module, state}
   - `:links`     -- list of Link structs
   - `:tick`      -- current tick counter
   - `:trace`     -- trace data
   - `:trace_enabled` -- whether tracing is active
   - `:input_streams` -- pending external input streams
  """

  alias ExSystolic.{Grid, Link, Space, Space.Grid2D, Trace}

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

  Delegates to the array's Space module to produce both internal
  (PE-to-PE) and boundary (external-input-to-PE) links for the given
  direction.  The set of valid directions is space-specific; Grid2D
  supports `:west_to_east` and `:north_to_south`.

  ## Examples

      iex> array = ExSystolic.Array.new(rows: 2, cols: 2) |> ExSystolic.Array.fill(ExSystolic.PE.MAC)
      iex> array = ExSystolic.Array.connect(array, :west_to_east)
      iex> length(array.links)
      4

  """
  @spec connect(t(), atom()) :: t()
  def connect(%{space: {space_mod, space_opts}, links: links} = array, direction) do
    new_links = space_mod.links(space_opts, direction)
    %{array | links: links ++ new_links}
  end

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

  `port` is an atom naming the PE port the stream enters through.
  Common values are `:west` and `:north` for Grid2D arrays, but any
  atom is accepted to support custom spaces with arbitrary port names.

  `stream_specs` is a list of `{coord, values}` where `values` is
  a list of items to inject one per tick into the PE at `coord`
  through `port`.

  Calling `input/3` for the same `{coord, port}` more than once raises
  `ArgumentError` -- duplicates are rejected to prevent silent data loss.

  ## Examples

      iex> array = ExSystolic.Array.new(rows: 2, cols: 2) |> ExSystolic.Array.fill(ExSystolic.PE.MAC)
      iex> array = ExSystolic.Array.connect(array, :west_to_east)
      iex> array = ExSystolic.Array.connect(array, :north_to_south)
      iex> array = ExSystolic.Array.input(array, :west, [{{0,0}, [1,2,3]}])
      iex> map_size(array.input_streams)
      1

  """
  @spec input(t(), atom(), [{Space.coord(), [term()]}]) :: t()
  def input(%{input_streams: streams} = array, port, stream_specs)
      when is_atom(port) do
    new_streams =
      Enum.reduce(stream_specs, streams, fn {coord, values}, acc ->
        key = {coord, port}

        if Map.has_key?(acc, key) do
          raise ArgumentError,
                "duplicate input stream for #{inspect(key)}; call Array.input/3 once per coord/port"
        end

        Map.put(acc, key, values)
      end)

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

  This function is **Grid2D-specific**: it relies on the array having
  rectangular `{row, col}` coordinates.  For arrays built on a custom
  `ExSystolic.Space`, use `result_map/1` instead.

  ## Examples

      iex> array = ExSystolic.Array.new(rows: 2, cols: 2) |> ExSystolic.Array.fill(ExSystolic.PE.MAC)
      iex> ExSystolic.Array.result_matrix(array)
      [[0, 0], [0, 0]]

  """
  @spec result_matrix(t()) :: [[term()]]
  def result_matrix(%{space: {Grid2D, _opts}, grid: grid, pes: pes}) do
    for r <- 0..(grid.rows - 1)//1 do
      for c <- 0..(grid.cols - 1)//1 do
        cell_state(pes, {r, c})
      end
    end
  end

  def result_matrix(%{space: {space_mod, _}}) do
    raise ArgumentError,
          "result_matrix/1 is Grid2D-only; got space #{inspect(space_mod)}. Use result_map/1 instead."
  end

  @doc """
  Returns a map of `coord => state` for every PE.

  Works for any Space implementation, not just Grid2D.

  ## Examples

      iex> array = ExSystolic.Array.new(rows: 2, cols: 2) |> ExSystolic.Array.fill(ExSystolic.PE.MAC)
      iex> ExSystolic.Array.result_map(array)
      %{{0, 0} => 0, {0, 1} => 0, {1, 0} => 0, {1, 1} => 0}

  """
  @spec result_map(t()) :: %{Space.coord() => term()}
  def result_map(%{pes: pes}) do
    for {coord, {_mod, state}} <- pes, into: %{}, do: {coord, state}
  end

  defp cell_state(pes, coord) do
    case Map.get(pes, coord) do
      {_mod, state} -> state
      nil -> nil
    end
  end
end
