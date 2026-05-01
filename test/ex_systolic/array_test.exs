defmodule ExSystolic.ArrayTest do
  use ExUnit.Case, async: true

  alias ExSystolic.{Array, PE.MAC}

  describe "new/1" do
    test "creates array with grid and no PEs" do
      array = Array.new(rows: 3, cols: 2)
      assert array.grid.rows == 3
      assert array.grid.cols == 2
      assert array.pes == %{}
      assert array.tick == 0
      assert array.trace_enabled == false
    end
  end

  describe "fill/2" do
    test "fills grid with MAC PEs" do
      array = Array.new(rows: 2, cols: 2) |> Array.fill(MAC)
      assert map_size(array.pes) == 4
      assert elem(array.pes[{0, 0}], 0) == MAC
      assert elem(array.pes[{0, 0}], 1) == 0
    end
  end

  describe "fill/3" do
    test "fills with per-PE options" do
      array = Array.new(rows: 1, cols: 1) |> Array.fill(MAC, %{{0, 0} => [acc: 99]})
      assert elem(array.pes[{0, 0}], 1) == 99
    end
  end

  describe "connect/2" do
    test "west_to_east creates boundary + internal links" do
      array = Array.new(rows: 2, cols: 3) |> Array.fill(MAC) |> Array.connect(:west_to_east)
      boundary_count = 2
      internal_count = 2 * (3 - 1)
      assert length(array.links) == boundary_count + internal_count
    end

    test "north_to_south creates boundary + internal links" do
      array = Array.new(rows: 2, cols: 3) |> Array.fill(MAC) |> Array.connect(:north_to_south)
      boundary_count = 3
      internal_count = (2 - 1) * 3
      assert length(array.links) == boundary_count + internal_count
    end

    test "both directions" do
      array =
        Array.new(rows: 2, cols: 2)
        |> Array.fill(MAC)
        |> Array.connect(:west_to_east)
        |> Array.connect(:north_to_south)

      we_boundary = 2
      we_internal = 2 * 1
      ns_boundary = 2
      ns_internal = 1 * 2
      assert length(array.links) == we_boundary + we_internal + ns_boundary + ns_internal
    end

    test "boundary links for west input target column 0" do
      array = Array.new(rows: 2, cols: 3) |> Array.fill(MAC) |> Array.connect(:west_to_east)
      boundary = Enum.find(array.links, &(&1.from == {{-1, 0}, :east}))
      assert boundary != nil
      assert boundary.to == {{0, 0}, :west}
      boundary1 = Enum.find(array.links, &(&1.from == {{-1, 1}, :east}))
      assert boundary1 != nil
      assert boundary1.to == {{1, 0}, :west}
    end

    test "boundary links for north input target row 0" do
      array = Array.new(rows: 2, cols: 3) |> Array.fill(MAC) |> Array.connect(:north_to_south)
      boundary0 = Enum.find(array.links, &(&1.from == {{0, -1}, :south}))
      assert boundary0 != nil
      assert boundary0.to == {{0, 0}, :north}
      boundary1 = Enum.find(array.links, &(&1.from == {{1, -1}, :south}))
      assert boundary1 != nil
      assert boundary1.to == {{0, 1}, :north}
    end

    test "1x1 grid still gets boundary links" do
      array = Array.new(rows: 1, cols: 1) |> Array.fill(MAC) |> Array.connect(:west_to_east) |> Array.connect(:north_to_south)
      assert length(array.links) == 2
    end
  end

  describe "input/3" do
    test "adds west input streams" do
      array = Array.new(rows: 2, cols: 2) |> Array.fill(MAC) |> Array.connect(:west_to_east)
      array = Array.input(array, :west, [{{0, 0}, [1, 2, 3]}, {{1, 0}, [4, 5, 6]}])
      assert Map.has_key?(array.input_streams, {{0, 0}, :west})
      assert Map.has_key?(array.input_streams, {{1, 0}, :west})
    end

    test "adds north input streams" do
      array = Array.new(rows: 2, cols: 2) |> Array.fill(MAC) |> Array.connect(:north_to_south)
      array = Array.input(array, :north, [{{0, 0}, [7, 8]}, {{0, 1}, [9, 10]}])
      assert Map.has_key?(array.input_streams, {{0, 0}, :north})
      assert Map.has_key?(array.input_streams, {{0, 1}, :north})
    end
  end

  describe "trace/2" do
    test "enables tracing" do
      array = Array.new(rows: 1, cols: 1) |> Array.trace(true)
      assert array.trace_enabled == true
    end

    test "disables tracing" do
      array = Array.new(rows: 1, cols: 1) |> Array.trace(true) |> Array.trace(false)
      assert array.trace_enabled == false
    end
  end

  describe "result_matrix/1" do
    test "extracts state as matrix" do
      array = Array.new(rows: 2, cols: 2) |> Array.fill(MAC)
      assert Array.result_matrix(array) == [[0, 0], [0, 0]]
    end
  end
end
