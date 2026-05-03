defmodule ExSystolic.TileTest do
  use ExUnit.Case, async: true

  alias ExSystolic.{Array, PE.MAC, Tile, TilePartitioner}

  describe "struct" do
    test "creates tile with required fields" do
      tile = %Tile{
        id: {0, 0},
        coords: [{0, 0}, {0, 1}],
        pes: %{{0, 0} => {MAC, 0}, {0, 1} => {MAC, 0}},
        links: []
      }

      assert tile.id == {0, 0}
      assert length(tile.coords) == 2
      assert map_size(tile.pes) == 2
    end

    test "raises when required fields are missing" do
      assert_raise ArgumentError, fn ->
        struct!(Tile, id: {0, 0})
      end
    end
  end

  describe "invariants from TilePartitioner" do
    setup do
      array =
        Array.new(rows: 4, cols: 4)
        |> Array.fill(MAC)
        |> Array.connect(:west_to_east)
        |> Array.connect(:north_to_south)

      tiles = TilePartitioner.partition(array, tile_rows: 2, tile_cols: 2)
      {:ok, tiles: tiles}
    end

    test "coords matches PE keys for every tile", %{tiles: tiles} do
      for tile <- tiles do
        assert MapSet.new(tile.coords) == MapSet.new(Map.keys(tile.pes))
      end
    end

    test "every link in tile.links has both endpoints inside tile.coords",
         %{tiles: tiles} do
      for tile <- tiles do
        coord_set = MapSet.new(tile.coords)

        for link <- tile.links do
          assert MapSet.member?(coord_set, elem(link.from, 0))
          assert MapSet.member?(coord_set, elem(link.to, 0))
        end
      end
    end

    test "no PE coordinate appears in two tiles", %{tiles: tiles} do
      all_coords = Enum.flat_map(tiles, & &1.coords)
      assert length(all_coords) == length(Enum.uniq(all_coords))
    end
  end
end
