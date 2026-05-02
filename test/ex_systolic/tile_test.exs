defmodule ExSystolic.TileTest do
  use ExUnit.Case, async: true

  alias ExSystolic.{PE.MAC, Tile}

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
      assert tile.boundary_inputs == %{}
    end
  end
end
