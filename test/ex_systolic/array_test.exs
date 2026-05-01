defmodule ExSystolic.ArrayTest do
  use ExUnit.Case, async: true

  alias ExSystolic.{Array, PE.MAC}

  defmodule DummySpace do
    @behaviour ExSystolic.Space

    @impl true
    def normalize({r, c}) when r >= 0 and c >= 0, do: {:ok, {r, c}}
    def normalize(_), do: {:error, :invalid}

    @impl true
    def neighbors({0, 0}, _opts), do: %{north: nil, south: {1, 0}, east: {0, 1}, west: nil}
    def neighbors({0, 1}, _opts), do: %{north: nil, south: {1, 1}, east: nil, west: {0, 0}}
    def neighbors({1, 0}, _opts), do: %{north: {0, 0}, south: nil, east: {1, 1}, west: nil}
    def neighbors({1, 1}, _opts), do: %{north: {0, 1}, south: nil, east: nil, west: {1, 0}}

    @impl true
    def ports(_coord, _opts), do: [:north, :south, :east, :west]

    @impl true
    def coords(_opts), do: [{0, 0}, {0, 1}, {1, 0}, {1, 1}]
  end

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

      assert length(array.links) == 8
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
      array =
        Array.new(rows: 1, cols: 1)
        |> Array.fill(MAC)
        |> Array.connect(:west_to_east)
        |> Array.connect(:north_to_south)

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

  describe "new/1 with space option" do
    test "creates array with custom space" do
      array = Array.new(space: {ExSystolic.Space.Grid2D, rows: 2, cols: 3})
      assert array.grid.rows == 2
      assert array.grid.cols == 3
      assert elem(array.space, 0) == ExSystolic.Space.Grid2D
    end

    test "default space is Grid2D" do
      array = Array.new(rows: 2, cols: 3)
      assert elem(array.space, 0) == ExSystolic.Space.Grid2D
      assert elem(array.space, 1) == [rows: 2, cols: 3]
    end

    test "space-based array produces same links as rows/cols" do
      space_array =
        Array.new(space: {ExSystolic.Space.Grid2D, rows: 2, cols: 2})
        |> Array.fill(MAC)
        |> Array.connect(:west_to_east)
        |> Array.connect(:north_to_south)

      classic_array =
        Array.new(rows: 2, cols: 2)
        |> Array.fill(MAC)
        |> Array.connect(:west_to_east)
        |> Array.connect(:north_to_south)

      assert length(space_array.links) == length(classic_array.links)

      space_set = MapSet.new(space_array.links)
      classic_set = MapSet.new(classic_array.links)
      assert MapSet.equal?(space_set, classic_set)
    end
  end

  describe "materialize_links/1" do
    test "creates bidirectional links for all neighbor relationships" do
      array =
        Array.new(rows: 2, cols: 2)
        |> Array.fill(MAC)
        |> Array.materialize_links()

      assert length(array.links) == 8
    end

    test "3x3 grid has correct number of bidirectional links" do
      array =
        Array.new(rows: 3, cols: 3)
        |> Array.fill(MAC)
        |> Array.materialize_links()

      horizontal_edges = 3 * 2
      vertical_edges = 2 * 3
      expected = (horizontal_edges + vertical_edges) * 2
      assert length(array.links) == expected
    end

    test "materialize_links creates only internal links (no boundary)" do
      array =
        Array.new(rows: 2, cols: 3)
        |> Array.fill(MAC)
        |> Array.materialize_links()

      boundary_links =
        Enum.filter(array.links, fn link ->
          elem(link.from, 0) |> elem(0) < 0 or elem(link.to, 0) |> elem(0) < 0
        end)

      assert boundary_links == []
    end

    test "every internal edge appears in both directions" do
      array =
        Array.new(rows: 2, cols: 2)
        |> Array.fill(MAC)
        |> Array.materialize_links()

      assert Enum.find(array.links, &(&1.from == {{0, 0}, :east} and &1.to == {{0, 1}, :west}))
      assert Enum.find(array.links, &(&1.from == {{0, 1}, :west} and &1.to == {{0, 0}, :east}))
    end
  end

  describe "result_matrix/1" do
    test "extracts state as matrix" do
      array = Array.new(rows: 2, cols: 2) |> Array.fill(MAC)
      assert Array.result_matrix(array) == [[0, 0], [0, 0]]
    end
  end

  describe "custom space" do
    test "creates array with custom space module" do
      array = Array.new(space: {DummySpace, []}, rows: 2, cols: 2)
      assert elem(array.space, 0) == DummySpace
      assert array.grid.rows == 2
    end

    test "connect with custom space uses generic materialization" do
      array =
        Array.new(space: {DummySpace, []}, rows: 2, cols: 2)
        |> Array.fill(MAC)
        |> Array.connect(:west_to_east)

      boundary =
        Enum.filter(array.links, fn link ->
          elem(link.from, 0) |> elem(0) < 0
        end)

      assert boundary != []
    end

    test "connect :north_to_south with custom space" do
      array =
        Array.new(space: {DummySpace, []}, rows: 2, cols: 2)
        |> Array.fill(MAC)
        |> Array.connect(:north_to_south)

      assert array.links != []
    end

    test "materialize_links with custom space" do
      array =
        Array.new(space: {DummySpace, []}, rows: 2, cols: 2)
        |> Array.fill(MAC)
        |> Array.materialize_links()

      assert length(array.links) == 8
    end
  end
end
