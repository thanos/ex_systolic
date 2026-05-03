defmodule ExSystolic.GridTest do
  use ExUnit.Case, async: true

  alias ExSystolic.Grid

  doctest Grid

  describe "rect/1" do
    test "creates a grid with given dimensions" do
      grid = Grid.rect(rows: 3, cols: 4)
      assert grid.rows == 3
      assert grid.cols == 4
    end

    test "raises on zero rows" do
      assert_raise ArgumentError, fn -> Grid.rect(rows: 0, cols: 2) end
    end

    test "raises on zero cols" do
      assert_raise ArgumentError, fn -> Grid.rect(rows: 2, cols: 0) end
    end
  end

  describe "neighbour lookups" do
    setup do
      {:ok, grid: Grid.rect(rows: 3, cols: 3)}
    end

    test "north of interior cell", %{grid: grid} do
      assert Grid.north(grid, {1, 1}) == {0, 1}
    end

    test "north of top row returns :none", %{grid: grid} do
      assert Grid.north(grid, {0, 1}) == :none
    end

    test "south of interior cell", %{grid: grid} do
      assert Grid.south(grid, {1, 1}) == {2, 1}
    end

    test "south of bottom row returns :none", %{grid: grid} do
      assert Grid.south(grid, {2, 1}) == :none
    end

    test "east of interior cell", %{grid: grid} do
      assert Grid.east(grid, {1, 1}) == {1, 2}
    end

    test "east of rightmost column returns :none", %{grid: grid} do
      assert Grid.east(grid, {1, 2}) == :none
    end

    test "west of interior cell", %{grid: grid} do
      assert Grid.west(grid, {1, 1}) == {1, 0}
    end

    test "west of leftmost column returns :none", %{grid: grid} do
      assert Grid.west(grid, {1, 0}) == :none
    end
  end

  describe "coords/1" do
    test "returns all coordinates in row-major order" do
      grid = Grid.rect(rows: 2, cols: 3)
      assert Grid.coords(grid) == [{0, 0}, {0, 1}, {0, 2}, {1, 0}, {1, 1}, {1, 2}]
    end
  end

  describe "member?/2" do
    test "in-bounds coordinate" do
      grid = Grid.rect(rows: 2, cols: 2)
      assert Grid.member?(grid, {1, 1})
    end

    test "out-of-bounds row" do
      grid = Grid.rect(rows: 2, cols: 2)
      refute Grid.member?(grid, {2, 0})
    end

    test "out-of-bounds column" do
      grid = Grid.rect(rows: 2, cols: 2)
      refute Grid.member?(grid, {0, 2})
    end
  end
end
