defmodule ExSystolic.Examples.GEMMTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias ExSystolic.Examples.GEMM

  describe "run/2" do
    test "empty matrices return empty result" do
      assert GEMM.run([], []) == []
    end

    test "1x1 identity" do
      assert GEMM.run([[1]], [[1]]) == [[1]]
    end

    test "2x2 multiplication" do
      a = [[1, 2], [3, 4]]
      b = [[5, 6], [7, 8]]
      assert GEMM.run(a, b) == [[19, 22], [43, 50]]
    end

    test "non-square: 2x3 times 3x2" do
      a = [[2, 0, 1], [3, 1, 2]]
      b = [[1, 2], [0, 3], [4, 1]]
      assert GEMM.run(a, b) == [[6, 5], [11, 11]]
    end

    test "1x3 times 3x1" do
      a = [[1, 2, 3]]
      b = [[4], [5], [6]]
      assert GEMM.run(a, b) == [[32]]
    end

    test "3x1 times 1x3" do
      a = [[1], [2], [3]]
      b = [[4, 5, 6]]
      assert GEMM.run(a, b) == [[4, 5, 6], [8, 10, 12], [12, 15, 18]]
    end

    test "zero matrix" do
      a = [[0, 0], [0, 0]]
      b = [[1, 2], [3, 4]]
      assert GEMM.run(a, b) == [[0, 0], [0, 0]]
    end

    test "identity matrix" do
      a = [[1, 0], [0, 1]]
      b = [[5, 6], [7, 8]]
      assert GEMM.run(a, b) == [[5, 6], [7, 8]]
    end

    test "3x3 multiplication" do
      a = [[1, 2, 3], [4, 5, 6], [7, 8, 9]]
      b = [[9, 8, 7], [6, 5, 4], [3, 2, 1]]

      expected = [
        [30, 24, 18],
        [84, 69, 54],
        [138, 114, 90]
      ]

      assert GEMM.run(a, b) == expected
    end
  end

  describe "west_streams/4" do
    test "skews rows of A with leading zeros" do
      streams = GEMM.west_streams([[1, 2], [3, 4]], 2, 2, 2)
      total = 2 + 2 + 2 - 1
      {_, row0} = Enum.find(streams, fn {{r, _}, _} -> r == 0 end)
      {_, row1} = Enum.find(streams, fn {{r, _}, _} -> r == 1 end)
      assert length(row0) == total
      assert length(row1) == total
      assert Enum.at(row0, 0) == 1
      assert Enum.at(row0, 1) == 2
      assert Enum.at(row1, 0) == 0
      assert Enum.at(row1, 1) == 3
      assert Enum.at(row1, 2) == 4
    end
  end

  describe "north_streams/4" do
    test "skews columns of B with leading zeros" do
      streams = GEMM.north_streams([[5, 6], [7, 8]], 2, 2, 2)
      total = 2 + 2 + 2 - 1
      {_, col0} = Enum.find(streams, fn {{_, c}, _} -> c == 0 end)
      {_, col1} = Enum.find(streams, fn {{_, c}, _} -> c == 1 end)
      assert length(col0) == total
      assert length(col1) == total
      assert Enum.at(col0, 0) == 5
      assert Enum.at(col0, 1) == 7
      assert Enum.at(col1, 0) == 0
      assert Enum.at(col1, 1) == 6
      assert Enum.at(col1, 2) == 8
    end
  end

  describe "determinism" do
    test "same inputs always produce same result" do
      a = [[1, 2], [3, 4]]
      b = [[5, 6], [7, 8]]
      result1 = GEMM.run(a, b)
      result2 = GEMM.run(a, b)
      assert result1 == result2
    end
  end

  describe "properties" do
    property "GEMM result matches reference multiplication for 2x2 matrices" do
      check all(
              a00 <- integer(-10..10),
              a01 <- integer(-10..10),
              a10 <- integer(-10..10),
              a11 <- integer(-10..10),
              b00 <- integer(-10..10),
              b01 <- integer(-10..10),
              b10 <- integer(-10..10),
              b11 <- integer(-10..10)
            ) do
        a = [[a00, a01], [a10, a11]]
        b = [[b00, b01], [b10, b11]]
        result = GEMM.run(a, b)

        expected = [
          [a00 * b00 + a01 * b10, a00 * b01 + a01 * b11],
          [a10 * b00 + a11 * b10, a10 * b01 + a11 * b11]
        ]

        assert result == expected
      end
    end

    property "GEMM is deterministic for any valid matrix" do
      check all(
              a <- list_of(list_of(integer(-5..5), length: 2), length: 2),
              b <- list_of(list_of(integer(-5..5), length: 2), length: 2)
            ) do
        assert GEMM.run(a, b) == GEMM.run(a, b)
      end
    end
  end
end
