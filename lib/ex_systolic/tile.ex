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
  - `:links` -- list of `Link.t()` internal to this tile (unused in
    current simplified backend, kept for future tile-local optimization)
  - `:boundary_inputs` -- map of `{coord, port} => value` from
    cross-boundary links (unused in current simplified backend)
  """

  alias ExSystolic.Link

  @type id :: term()

  @type t :: %__MODULE__{
          id: id(),
          coords: [ExSystolic.Grid.coord()],
          pes: %{ExSystolic.Grid.coord() => {module(), ExSystolic.PE.state()}},
          links: [Link.t()],
          boundary_inputs: %{{ExSystolic.Grid.coord(), atom()} => term()}
        }

  @enforce_keys [:id, :coords, :pes, :links]
  defstruct [:id, :coords, :pes, :links, boundary_inputs: %{}]
end
