defmodule ExSystolic.Backend.PartitionedTest do
  use ExUnit.Case, async: true

  alias ExSystolic.{Array, Backend.Partitioned, Clock, Examples.GEMM, PE.MAC}

  doctest ExSystolic.Backend.Partitioned

  describe "run/2" do
    test "runs array for given number of ticks" do
      array =
        Array.new(rows: 2, cols: 2)
        |> Array.fill(MAC)
        |> Array.connect(:west_to_east)
        |> Array.connect(:north_to_south)
        |> Array.input(:west, [{{0, 0}, [1, 2]}, {{1, 0}, [3, 4]}])
        |> Array.input(:north, [{{0, 0}, [5, 7]}, {{0, 1}, [6, 8]}])

      result = Partitioned.run(array, ticks: 5)
      assert result.tick == 5
    end

    test "with ticks: 0 returns unchanged array" do
      array =
        Array.new(rows: 2, cols: 2)
        |> Array.fill(MAC)
        |> Array.connect(:west_to_east)
        |> Array.connect(:north_to_south)

      result = Partitioned.run(array, ticks: 0)
      assert result.tick == 0
    end
  end

  describe "determinism parity with interpreted backend" do
    test "2x2 GEMM produces identical results" do
      a = [[1, 2], [3, 4]]
      b = [[5, 6], [7, 8]]

      interpreted_result = GEMM.run(a, b)

      array =
        Array.new(rows: 2, cols: 2)
        |> Array.fill(MAC)
        |> Array.connect(:west_to_east)
        |> Array.connect(:north_to_south)
        |> Array.input(:west, GEMM.west_streams(a, 2, 2, 2))
        |> Array.input(:north, GEMM.north_streams(b, 2, 2, 2))

      partitioned_result = Partitioned.run(array, ticks: 5)
      partitioned_matrix = Array.result_matrix(partitioned_result)

      assert partitioned_matrix == interpreted_result
    end

    test "3x3 GEMM produces identical results" do
      a = [[1, 2, 3], [4, 5, 6], [7, 8, 9]]
      b = [[10, 11, 12], [13, 14, 15], [16, 17, 18]]

      interpreted_result = GEMM.run(a, b)

      array =
        Array.new(rows: 3, cols: 3)
        |> Array.fill(MAC)
        |> Array.connect(:west_to_east)
        |> Array.connect(:north_to_south)
        |> Array.input(:west, GEMM.west_streams(a, 3, 3, 3))
        |> Array.input(:north, GEMM.north_streams(b, 3, 3, 3))

      partitioned_result = Partitioned.run(array, ticks: 7)
      partitioned_matrix = Array.result_matrix(partitioned_result)

      assert partitioned_matrix == interpreted_result
    end

    test "4x4 GEMM with 2x2 tiles produces identical results" do
      a = [[1, 2, 3, 4], [5, 6, 7, 8], [9, 10, 11, 12], [13, 14, 15, 16]]
      b = [[17, 18, 19, 20], [21, 22, 23, 24], [25, 26, 27, 28], [29, 30, 31, 32]]

      interpreted_result = GEMM.run(a, b)

      array =
        Array.new(rows: 4, cols: 4)
        |> Array.fill(MAC)
        |> Array.connect(:west_to_east)
        |> Array.connect(:north_to_south)
        |> Array.input(:west, GEMM.west_streams(a, 4, 4, 4))
        |> Array.input(:north, GEMM.north_streams(b, 4, 4, 4))

      partitioned_result =
        Partitioned.run(array, ticks: 11, tile_rows: 2, tile_cols: 2)

      partitioned_matrix = Array.result_matrix(partitioned_result)

      assert partitioned_matrix == interpreted_result
    end

    test "repeated runs produce identical results (parallel determinism)" do
      a = [[1, 2], [3, 4]]
      b = [[5, 6], [7, 8]]

      results =
        for _ <- 1..5 do
          array =
            Array.new(rows: 2, cols: 2)
            |> Array.fill(MAC)
            |> Array.connect(:west_to_east)
            |> Array.connect(:north_to_south)
            |> Array.input(:west, GEMM.west_streams(a, 2, 2, 2))
            |> Array.input(:north, GEMM.north_streams(b, 2, 2, 2))

          Partitioned.run(array, ticks: 5)
          |> Array.result_matrix()
        end

      assert Enum.uniq(results) == [hd(results)]
    end

    test "full PE state parity with interpreted backend (beyond result_matrix)" do
      a = [[1, 2], [3, 4]]
      b = [[5, 6], [7, 8]]

      array =
        Array.new(rows: 2, cols: 2)
        |> Array.fill(MAC)
        |> Array.connect(:west_to_east)
        |> Array.connect(:north_to_south)
        |> Array.input(:west, GEMM.west_streams(a, 2, 2, 2))
        |> Array.input(:north, GEMM.north_streams(b, 2, 2, 2))

      interp = Clock.run(%{array | pes: array.pes}, ticks: 5, backend: :interpreted)
      part = Partitioned.run(array, ticks: 5)

      interp_states = for {coord, {_, s}} <- interp.pes, into: %{}, do: {coord, s}
      part_states = for {coord, {_, s}} <- part.pes, into: %{}, do: {coord, s}

      assert interp_states == part_states
    end
  end

  describe "edge cases" do
    test "input stream with no matching link is silently dropped" do
      array =
        Array.new(rows: 1, cols: 1)
        |> Array.fill(MAC)
        |> Array.input(:west, [{{99, 99}, [1, 2, 3]}])

      result = Partitioned.run(array, ticks: 1)
      assert result.input_streams == %{}
    end

    test "input stream exhausted mid-run is removed from remaining" do
      array =
        Array.new(rows: 1, cols: 1)
        |> Array.fill(MAC)
        |> Array.connect(:west_to_east)
        |> Array.connect(:north_to_south)
        |> Array.input(:west, [{{0, 0}, [10]}])
        |> Array.input(:north, [{{0, 0}, [5]}])

      result = Partitioned.run(array, ticks: 3)
      refute Map.has_key?(result.input_streams, {{0, 0}, :west})
    end

    test "link full defers remaining stream values" do
      array =
        Array.new(rows: 1, cols: 1)
        |> Array.fill(MAC)
        |> Array.connect(:west_to_east)
        |> Array.connect(:north_to_south)
        |> Array.input(:west, [{{0, 0}, Enum.to_list(1..20)}])
        |> Array.input(:north, [{{0, 0}, [5]}])

      result = Partitioned.run(array, ticks: 1)
      remaining = result.input_streams[{{0, 0}, :west}]
      assert remaining != []
    end

    test "step with trace enabled records events" do
      array =
        Array.new(rows: 1, cols: 1)
        |> Array.fill(MAC)
        |> Array.connect(:west_to_east)
        |> Array.connect(:north_to_south)
        |> Array.input(:west, [{{0, 0}, [3]}])
        |> Array.input(:north, [{{0, 0}, [4]}])
        |> Array.trace(true)

      result = Partitioned.step(array)
      assert result.trace.events != []
    end

    test "step with trace disabled has no events" do
      array =
        Array.new(rows: 1, cols: 1)
        |> Array.fill(MAC)
        |> Array.trace(false)

      result = Partitioned.step(array)
      assert result.trace.events == []
    end

    test "step with empty input stream skips injection" do
      array =
        Array.new(rows: 1, cols: 1)
        |> Array.fill(MAC)
        |> Array.connect(:west_to_east)
        |> Array.connect(:north_to_south)
        |> Array.input(:west, [{{0, 0}, []}])
        |> Array.input(:north, [{{0, 0}, []}])

      result = Partitioned.step(array)
      assert result.tick == 1
    end

    test "step with pre-filled link defers injection (:full branch)" do
      array =
        Array.new(rows: 1, cols: 1)
        |> Array.fill(MAC)
        |> Array.connect(:west_to_east)
        |> Array.connect(:north_to_south)
        |> Array.input(:west, [{{0, 0}, [3]}])
        |> Array.input(:north, [{{0, 0}, [4]}])

      after_tick1 = Partitioned.step(array)

      {:ok, full_link} =
        ExSystolic.Link.write(
          Enum.find(after_tick1.links, &(&1.to == {{0, 0}, :west})),
          99
        )

      pre_filled = %{
        after_tick1
        | links:
            Enum.map(after_tick1.links, fn l ->
              if l.to == {{0, 0}, :west}, do: full_link, else: l
            end),
          input_streams: %{{{0, 0}, :west} => [100, 101]}
      }

      result = Partitioned.step(pre_filled)
      remaining = result.input_streams[{{0, 0}, :west}]
      assert remaining != []
    end
  end

  describe "Clock backend selection" do
    test "Clock.run with backend: :partitioned produces same result as :interpreted" do
      a = [[1, 2], [3, 4]]
      b = [[5, 6], [7, 8]]

      interpreted =
        Array.new(rows: 2, cols: 2)
        |> Array.fill(MAC)
        |> Array.connect(:west_to_east)
        |> Array.connect(:north_to_south)
        |> Array.input(:west, GEMM.west_streams(a, 2, 2, 2))
        |> Array.input(:north, GEMM.north_streams(b, 2, 2, 2))
        |> Clock.run(ticks: 5)
        |> Array.result_matrix()

      partitioned =
        Array.new(rows: 2, cols: 2)
        |> Array.fill(MAC)
        |> Array.connect(:west_to_east)
        |> Array.connect(:north_to_south)
        |> Array.input(:west, GEMM.west_streams(a, 2, 2, 2))
        |> Array.input(:north, GEMM.north_streams(b, 2, 2, 2))
        |> Clock.run(ticks: 5, backend: :partitioned)
        |> Array.result_matrix()

      assert interpreted == partitioned
    end

    test "Clock.run with dispatch: :pool produces same result as :interpreted" do
      a = [[1, 2], [3, 4]]
      b = [[5, 6], [7, 8]]

      interpreted =
        Array.new(rows: 2, cols: 2)
        |> Array.fill(MAC)
        |> Array.connect(:west_to_east)
        |> Array.connect(:north_to_south)
        |> Array.input(:west, GEMM.west_streams(a, 2, 2, 2))
        |> Array.input(:north, GEMM.north_streams(b, 2, 2, 2))
        |> Clock.run(ticks: 5, backend: :interpreted)
        |> Array.result_matrix()

      pooled =
        Array.new(rows: 2, cols: 2)
        |> Array.fill(MAC)
        |> Array.connect(:west_to_east)
        |> Array.connect(:north_to_south)
        |> Array.input(:west, GEMM.west_streams(a, 2, 2, 2))
        |> Array.input(:north, GEMM.north_streams(b, 2, 2, 2))
        |> Clock.run(ticks: 5, backend: :partitioned, dispatch: :pool)
        |> Array.result_matrix()

      assert interpreted == pooled
    end

    test "invalid dispatch strategy raises ArgumentError" do
      array =
        Array.new(rows: 1, cols: 1)
        |> Array.fill(MAC)

      assert_raise ArgumentError, ~r/unknown dispatch strategy/, fn ->
        Partitioned.run(array, ticks: 1, dispatch: :bad)
      end
    end
  end
end
