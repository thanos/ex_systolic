defmodule ExSystolic.Backend.ConformanceTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias ExSystolic.{Array, Clock, Examples.GEMM, PE.MAC}

  defmodule Fixtures do
    @moduledoc false

    def gemm_2x2 do
      a = [[1, 2], [3, 4]]
      b = [[5, 6], [7, 8]]
      expected = GEMM.run(a, b)

      array =
        Array.new(rows: 2, cols: 2)
        |> Array.fill(MAC)
        |> Array.connect(:west_to_east)
        |> Array.connect(:north_to_south)
        |> Array.input(:west, GEMM.west_streams(a, 2, 2, 2))
        |> Array.input(:north, GEMM.north_streams(b, 2, 2, 2))

      {array, 5, expected}
    end

    def gemm_3x3 do
      a = [[1, 2, 3], [4, 5, 6], [7, 8, 9]]
      b = [[10, 11, 12], [13, 14, 15], [16, 17, 18]]
      expected = GEMM.run(a, b)

      array =
        Array.new(rows: 3, cols: 3)
        |> Array.fill(MAC)
        |> Array.connect(:west_to_east)
        |> Array.connect(:north_to_south)
        |> Array.input(:west, GEMM.west_streams(a, 3, 3, 3))
        |> Array.input(:north, GEMM.north_streams(b, 3, 3, 3))

      {array, 7, expected}
    end

    def single_pe do
      array =
        Array.new(rows: 1, cols: 1)
        |> Array.fill(MAC)
        |> Array.connect(:west_to_east)
        |> Array.connect(:north_to_south)
        |> Array.input(:west, [{{0, 0}, [3, 7]}])
        |> Array.input(:north, [{{0, 0}, [4, 2]}])

      {array, 3, nil}
    end

    def sparse_input do
      array =
        Array.new(rows: 2, cols: 2)
        |> Array.fill(MAC)
        |> Array.connect(:west_to_east)
        |> Array.connect(:north_to_south)
        |> Array.input(:west, [{{0, 0}, [1]}, {{1, 0}, [2]}])
        |> Array.input(:north, [{{0, 0}, [3]}, {{0, 1}, [4]}])

      {array, 3, nil}
    end
  end

  defp run_via_clock(array, ticks, :interpreted) do
    Clock.run(array, ticks: ticks, backend: :interpreted)
  end

  defp run_via_clock(array, ticks, {:partitioned, opts}) do
    Clock.run(array, Keyword.put(opts, :ticks, ticks) ++ [backend: :partitioned])
  end

  defp run_via_clock(array, ticks, :partitioned) do
    Clock.run(array, ticks: ticks, backend: :partitioned)
  end

  defp assert_result_parity(backends, fixture_fun) do
    {array, ticks, _expected} = fixture_fun.()

    results =
      for backend <- backends do
        run_via_clock(array, ticks, backend)
        |> Array.result_map()
      end

    [reference | others] = results

    for result <- others do
      assert result == reference, "Result parity failed for #{inspect(backends)}"
    end
  end

  defp assert_trace_parity(backends, fixture_fun) do
    {array, ticks, _expected} = fixture_fun.()
    array = Array.trace(array, true)

    results =
      for backend <- backends do
        run_via_clock(array, ticks, backend)
      end

    [ref | others] = results

    ref_events =
      ref.trace.events
      |> Enum.map(&{&1.tick, &1.coord, &1.state_before, &1.state_after})
      |> Enum.sort()

    for result <- others do
      result_events =
        result.trace.events
        |> Enum.map(&{&1.tick, &1.coord, &1.state_before, &1.state_after})
        |> Enum.sort()

      assert result_events == ref_events,
             "Trace parity failed for #{inspect(backends)}"
    end
  end

  describe "result parity across backends" do
    test "2x2 GEMM: interpreted == partitioned" do
      assert_result_parity([:interpreted, :partitioned], &Fixtures.gemm_2x2/0)
    end

    test "3x3 GEMM: interpreted == partitioned" do
      assert_result_parity([:interpreted, :partitioned], &Fixtures.gemm_3x3/0)
    end

    test "single PE: interpreted == partitioned" do
      assert_result_parity([:interpreted, :partitioned], &Fixtures.single_pe/0)
    end

    test "sparse input: interpreted == partitioned" do
      assert_result_parity([:interpreted, :partitioned], &Fixtures.sparse_input/0)
    end

    test "2x2 GEMM with 1x1 tiles: interpreted == partitioned(tile_rows:1, tile_cols:1)" do
      assert_result_parity(
        [:interpreted, {:partitioned, tile_rows: 1, tile_cols: 1}],
        &Fixtures.gemm_2x2/0
      )
    end

    test "2x2 GEMM with 1x2 tiles: interpreted == partitioned(tile_rows:1, tile_cols:2)" do
      assert_result_parity(
        [:interpreted, {:partitioned, tile_rows: 1, tile_cols: 2}],
        &Fixtures.gemm_2x2/0
      )
    end
  end

  describe "trace parity across backends" do
    test "2x2 GEMM trace: interpreted == partitioned" do
      assert_trace_parity([:interpreted, :partitioned], &Fixtures.gemm_2x2/0)
    end

    test "single PE trace: interpreted == partitioned" do
      assert_trace_parity([:interpreted, :partitioned], &Fixtures.single_pe/0)
    end
  end

  describe "result matches expected" do
    test "2x2 GEMM interpreted matches GEMM.run" do
      {array, ticks, expected} = Fixtures.gemm_2x2()
      result = Clock.run(array, ticks: ticks, backend: :interpreted) |> Array.result_matrix()
      assert result == expected
    end

    test "2x2 GEMM partitioned matches GEMM.run" do
      {array, ticks, expected} = Fixtures.gemm_2x2()
      result = Clock.run(array, ticks: ticks, backend: :partitioned) |> Array.result_matrix()
      assert result == expected
    end

    test "3x3 GEMM interpreted matches GEMM.run" do
      {array, ticks, expected} = Fixtures.gemm_3x3()
      result = Clock.run(array, ticks: ticks, backend: :interpreted) |> Array.result_matrix()
      assert result == expected
    end
  end
end
