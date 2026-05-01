defmodule ExSystolic.Space.Grid2DTest do
  use ExUnit.Case, async: true

  alias ExSystolic.Space.Grid2D

  describe "normalize/1" do
    test "accepts valid {row, col} tuple" do
      assert Grid2D.normalize({0, 0}) == {:ok, {0, 0}}
      assert Grid2D.normalize({2, 5}) == {:ok, {2, 5}}
    end

    test "rejects negative indices" do
      assert Grid2D.normalize({-1, 0}) == {:error, :invalid_coordinate}
      assert Grid2D.normalize({0, -1}) == {:error, :invalid_coordinate}
    end

    test "rejects non-tuple input" do
      assert Grid2D.normalize("bad") == {:error, :invalid_coordinate}
      assert Grid2D.normalize(42) == {:error, :invalid_coordinate}
      assert Grid2D.normalize({1.0, 2}) == {:error, :invalid_coordinate}
    end
  end

  describe "neighbors/2" do
    test "interior cell has all four neighbors" do
      assert Grid2D.neighbors({1, 1}, rows: 3, cols: 3) ==
               %{north: {0, 1}, south: {2, 1}, east: {1, 2}, west: {1, 0}}
    end

    test "top-left corner has nil north and west" do
      neighbors = Grid2D.neighbors({0, 0}, rows: 3, cols: 3)
      assert neighbors.north == nil
      assert neighbors.west == nil
      assert neighbors.south == {1, 0}
      assert neighbors.east == {0, 1}
    end

    test "bottom-right corner has nil south and east" do
      neighbors = Grid2D.neighbors({2, 2}, rows: 3, cols: 3)
      assert neighbors.south == nil
      assert neighbors.east == nil
      assert neighbors.north == {1, 2}
      assert neighbors.west == {2, 1}
    end

    test "1x1 grid has all nil neighbors" do
      neighbors = Grid2D.neighbors({0, 0}, rows: 1, cols: 1)
      assert neighbors == %{north: nil, south: nil, east: nil, west: nil}
    end

    test "top edge has nil north" do
      neighbors = Grid2D.neighbors({0, 1}, rows: 3, cols: 3)
      assert neighbors.north == nil
      assert neighbors.south == {1, 1}
    end

    test "left edge has nil west" do
      neighbors = Grid2D.neighbors({1, 0}, rows: 3, cols: 3)
      assert neighbors.west == nil
      assert neighbors.east == {1, 1}
    end
  end

  describe "ports/2" do
    test "always returns four directional ports" do
      assert Grid2D.ports({0, 0}, rows: 2, cols: 2) == [:north, :south, :east, :west]
      assert Grid2D.ports({1, 1}, rows: 2, cols: 2) == [:north, :south, :east, :west]
    end
  end

  describe "coords/1" do
    test "returns all coordinates in row-major order" do
      assert Grid2D.coords(rows: 2, cols: 3) ==
               [{0, 0}, {0, 1}, {0, 2}, {1, 0}, {1, 1}, {1, 2}]
    end

    test "1x1 grid returns single coordinate" do
      assert Grid2D.coords(rows: 1, cols: 1) == [{0, 0}]
    end
  end

  describe "doctests" do
    doctest Grid2D
  end
end
