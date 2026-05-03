defmodule ExSystolic.TilePartitioner do
  @moduledoc """
  Partitions a systolic array into rectangular tiles.

  The default strategy divides the grid into approximately equal-sized
  rectangular tiles.  Tile size is configurable via the `tile_rows:`
  and `tile_cols:` options.

  ## Why tiles?

  Tiles balance granularity and locality:

  - Too fine (1 PE per tile) -- excessive coordination overhead
  - Too coarse (1 tile for the whole array) -- no parallelism
  - Just right -- good data locality, parallel across tiles

  ## Partitioning algorithm

  Given a grid of `rows x cols` and tile size `tr x tc`:

  - The grid is divided into `ceil(rows/tr) x ceil(cols/tc)` tiles
  - Edge tiles may be smaller than `tr x tc`
  - Each tile owns the PEs and **internal** links within its bounds
  - A link is **internal** to a tile when both its `from` and `to`
    endpoints are coordinates within that tile
  - Links crossing tile boundaries (where one endpoint is in a
    different tile) are **not** assigned to any tile; they are managed
    globally by the partitioned backend's BSP read/write cycle

  ## Examples

      iex> alias ExSystolic.{Array, TilePartitioner, PE.MAC}
      iex> array = Array.new(rows: 4, cols: 4) |> Array.fill(MAC) |> Array.connect(:west_to_east) |> Array.connect(:north_to_south)
      iex> tiles = TilePartitioner.partition(array, tile_rows: 2, tile_cols: 2)
      iex> length(tiles)
      4
      iex> hd(tiles).id
      {0, 0}

  """

  alias ExSystolic.{Array, Tile}

  @doc """
  Partitions an array into tiles.

  ## Options

  - `:tile_rows` -- number of rows per tile (default: `rows`)
  - `:tile_cols` -- number of columns per tile (default: `cols`)

  When no tile dimensions are given, the entire array becomes a single
  tile (equivalent to the interpreted backend).

  ## Examples

      iex> alias ExSystolic.{Array, TilePartitioner, PE.MAC}
      iex> array = Array.new(rows: 3, cols: 3) |> Array.fill(MAC)
      iex> tiles = TilePartitioner.partition(array, tile_rows: 2, tile_cols: 2)
      iex> length(tiles)
      4

  """
  @spec partition(Array.t(), keyword()) :: [Tile.t()]
  def partition(array, opts \\ []) do
    rows = array.grid.rows
    cols = array.grid.cols
    tile_rows = Keyword.get(opts, :tile_rows, rows)
    tile_cols = Keyword.get(opts, :tile_cols, cols)

    validate_tile_dim!(:tile_rows, tile_rows)
    validate_tile_dim!(:tile_cols, tile_cols)

    row_chunks = Enum.chunk_every(0..(rows - 1)//1, tile_rows)
    col_chunks = Enum.chunk_every(0..(cols - 1)//1, tile_cols)

    for row_chunk <- row_chunks,
        col_chunk <- col_chunks do
      build_tile(array, row_chunk, col_chunk)
    end
  end

  defp validate_tile_dim!(_name, n) when is_integer(n) and n > 0, do: :ok

  defp validate_tile_dim!(name, n) do
    raise ArgumentError, "#{name} must be a positive integer, got #{inspect(n)}"
  end

  defp build_tile(array, row_chunk, col_chunk) do
    coords =
      for r <- row_chunk,
          c <- col_chunk do
        {r, c}
      end

    coord_set = Map.new(coords, &{&1, true})
    pes = Map.take(array.pes, coords)

    local_links =
      Enum.filter(array.links, fn link ->
        Map.has_key?(coord_set, elem(link.from, 0)) and
          Map.has_key?(coord_set, elem(link.to, 0))
      end)

    %Tile{
      id: {hd(row_chunk), hd(col_chunk)},
      coords: coords,
      pes: pes,
      links: local_links
    }
  end
end
