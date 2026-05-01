defmodule ExSystolic.Space do
  @moduledoc """
  Behaviour defining the spatial model of a systolic array.

  A Space is responsible for three things:

  1. **Coordinate validation** -- is a given term a valid coordinate in
     this space?
  2. **Neighbour relationships** -- given a coordinate, what are its
     neighbours and which port connects to each?
  3. **Port definitions** -- which named ports does a coordinate expose?

  ## Design intent

  The Space abstraction separates *where things are* from *what they
  do*.  The PE behaviour, Clock, Link, and Trace modules remain
  completely unaware of the space.  Only the Array module consults the
  space when constructing links or enumerating coordinates.

  This means you can introduce a graph topology, a hierarchical layout,
  or a vector space in a future phase without touching execution logic.

  ## Implementing a custom space

  Any module that implements the three callbacks below can serve as a
  space.  The `opts` argument lets the same module serve multiple
  configurations (e.g. different grid sizes).

      defmodule MyGraphSpace do
        @behaviour ExSystolic.Space

        @impl true
        def normalize({node_id, _} = coord), do: {:ok, coord}

        @impl true
        def neighbors(coord, adjacency) do
          Map.get(adjacency, coord, %{})
        end

        @impl true
        def ports(_coord, _opts), do: [:in, :out]
      end
  """

  @type coord :: term()

  @doc """
  Validates and normalizes a coordinate term.

  Returns `{:ok, coord}` if the term is a valid coordinate in this
  space, or `{:error, reason}` otherwise.  Normalization may transform
  the term into a canonical form.
  """
  @callback normalize(term()) :: {:ok, coord()} | {:error, term()}

  @doc """
  Returns the neighbours of a coordinate as a map of port => neighbour_coord.

  Ports that have no neighbour (boundary) should map to `nil`.
  """
  @callback neighbors(coord(), opts :: term()) :: %{optional(atom()) => coord() | nil}

  @doc """
  Returns the list of port names that a coordinate exposes.

  This determines which input/output ports the PE at that coordinate
  will use.
  """
  @callback ports(coord(), opts :: term()) :: [atom()]
end
