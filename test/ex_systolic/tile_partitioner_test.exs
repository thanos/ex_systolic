defmodule ExSystolic.TilePartitionerTest do
  use ExUnit.Case, async: true

  alias ExSystolic.{Array, PE.MAC, TilePartitioner}

  describe "partition/2" do
    test "single tile when no tile dimensions given" do
      array = Array.new(rows: 4, cols: 4) |> Array.fill(MAC)
      tiles = TilePartitioner.partition(array)
      assert length(tiles) == 1
    end

    test "2x2 grid with 2x2 tile size produces 1 tile" do
      array = Array.new(rows: 2, cols: 2) |> Array.fill(MAC)
      tiles = TilePartitioner.partition(array, tile_rows: 2, tile_cols: 2)
      assert length(tiles) == 1
    end

    test "4x4 grid with 2x2 tiles produces 4 tiles" do
      array = Array.new(rows: 4, cols: 4) |> Array.fill(MAC)
      tiles = TilePartitioner.partition(array, tile_rows: 2, tile_cols: 2)
      assert length(tiles) == 4
    end

    test "every PE appears in exactly one tile" do
      array = Array.new(rows: 4, cols: 4) |> Array.fill(MAC)
      tiles = TilePartitioner.partition(array, tile_rows: 2, tile_cols: 2)

      all_coords =
        tiles
        |> Enum.flat_map(& &1.coords)
        |> MapSet.new()

      expected_coords =
        for r <- 0..3, c <- 0..3, into: MapSet.new() do
          {r, c}
        end

      assert MapSet.equal?(all_coords, expected_coords)
    end

    test "tile IDs are {row_start, col_start}" do
      array = Array.new(rows: 4, cols: 4) |> Array.fill(MAC)
      tiles = TilePartitioner.partition(array, tile_rows: 2, tile_cols: 2)
      ids = Enum.map(tiles, & &1.id) |> MapSet.new()
      assert MapSet.equal?(ids, MapSet.new([{0, 0}, {0, 2}, {2, 0}, {2, 2}]))
    end

    test "internal links are assigned to the tile containing both endpoints" do
      array =
        Array.new(rows: 4, cols: 4)
        |> Array.fill(MAC)
        |> Array.connect(:west_to_east)
        |> Array.connect(:north_to_south)

      tiles = TilePartitioner.partition(array, tile_rows: 2, tile_cols: 2)

      for tile <- tiles do
        for link <- tile.links do
          from_coord = elem(link.from, 0)
          to_coord = elem(link.to, 0)
          coord_set = MapSet.new(tile.coords)
          assert MapSet.member?(coord_set, from_coord)
          assert MapSet.member?(coord_set, to_coord)
        end
      end
    end

    test "3x3 grid with 2x2 tiles handles uneven division" do
      array = Array.new(rows: 3, cols: 3) |> Array.fill(MAC)
      tiles = TilePartitioner.partition(array, tile_rows: 2, tile_cols: 2)
      assert length(tiles) == 4

      all_coords = Enum.flat_map(tiles, & &1.coords)
      assert length(all_coords) == 9
    end
  end
end
