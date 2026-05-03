defmodule ExSystolic.Tile do
  @moduledoc """
  A rectangular partition of a systolic array.

  A tile owns a subset of the array's PEs.  In the partitioned backend,
  tiles are used to group PE executions for parallel dispatch.

  ## BSP execution model

  Each tick, the partitioned backend:

  1. Reads all link buffers globally (before any PE executes)
  2. Dispatches tile PE computations in parallel
  3. Collects results and writes outputs into links

  The tile itself is just a grouping mechanism -- it carries a subset
  of PE states and coordinates.  The actual link I/O is managed
  centrally by the backend.

  ## Structure

  - `:id` -- unique identifier (typically `{row_start, col_start}`)
  - `:coords` -- list of PE coordinates owned by this tile
  - `:pes` -- map of `coord => {module, state}`
  - `:links` -- list of `Link.t()` internal to this tile (i.e. both
    endpoints lie within `:coords`).  Currently unused by the
    centralized-link backend, retained as documentation for future
    tile-local optimization.

  ## Invariants

  - `coord_set = MapSet.new(coords) == MapSet.new(Map.keys(pes))`
  - Every link in `:links` has both `from` and `to` coords in
    `coord_set`.

  ## Example

      iex> alias ExSystolic.{PE.MAC, Tile}
      iex> tile = %Tile{
      ...>   id: {0, 0},
      ...>   coords: [{0, 0}, {0, 1}],
      ...>   pes: %{{0, 0} => {MAC, 0}, {0, 1} => {MAC, 0}},
      ...>   links: []
      ...> }
      iex> tile.id
      {0, 0}
  """

  alias ExSystolic.Link

  @type id :: term()

  @type t :: %__MODULE__{
          id: id(),
          coords: [ExSystolic.Grid.coord()],
          pes: %{ExSystolic.Grid.coord() => {module(), ExSystolic.PE.state()}},
          links: [Link.t()]
        }

  @enforce_keys [:id, :coords, :pes, :links]
  defstruct [:id, :coords, :pes, :links]
end
