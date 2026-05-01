defmodule ExSystolic.PE.MACTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias ExSystolic.PE.MAC

  describe "init/1" do
    test "default accumulator is 0" do
      assert MAC.init([]) == 0
    end

    test "custom initial accumulator" do
      assert MAC.init(acc: 42) == 42
    end
  end

  describe "step/4" do
    test "multiply and accumulate" do
      {state, outputs} = MAC.step(0, %{west: 3, north: 4}, 0, %{})
      assert state == 12
      assert outputs.result == 12
    end

    test "accumulate over multiple steps" do
      {s1, _o1} = MAC.step(0, %{west: 2, north: 3}, 0, %{})
      assert s1 == 6
      {s2, o2} = MAC.step(s1, %{west: 4, north: 5}, 1, %{})
      assert s2 == 26
      assert o2.result == 26
    end

    test "forwards a east" do
      {_, outputs} = MAC.step(0, %{west: 7, north: 1}, 0, %{})
      assert outputs.east == 7
    end

    test "forwards b south" do
      {_, outputs} = MAC.step(0, %{west: 1, north: 9}, 0, %{})
      assert outputs.south == 9
    end

    test "missing west input: no east output, acc unaffected" do
      {state, outputs} = MAC.step(0, %{north: 5}, 0, %{})
      assert state == 0
      refute Map.has_key?(outputs, :east)
      assert outputs.south == 5
    end

    test "missing north input: no south output, acc unaffected" do
      {state, outputs} = MAC.step(0, %{west: 5}, 0, %{})
      assert state == 0
      assert outputs.east == 5
      refute Map.has_key?(outputs, :south)
    end

    test "empty input treated as absent" do
      {state, outputs} = MAC.step(10, %{west: :empty, north: :empty}, 0, %{})
      assert state == 10
      refute Map.has_key?(outputs, :east)
      refute Map.has_key?(outputs, :south)
      assert outputs.result == 10
    end

    test "both inputs empty" do
      {state, _outputs} = MAC.step(0, %{west: :empty, north: :empty}, 0, %{})
      assert state == 0
    end

    test "explicit zero is forwarded" do
      {state, outputs} = MAC.step(0, %{west: 0, north: 5}, 0, %{})
      assert state == 0
      assert outputs.east == 0
      assert outputs.south == 5
    end

    test "both inputs absent" do
      {state, outputs} = MAC.step(7, %{}, 0, %{})
      assert state == 7
      assert outputs.result == 7
      refute Map.has_key?(outputs, :east)
      refute Map.has_key?(outputs, :south)
    end
  end

  describe "PE behaviour compliance" do
    test "MAC implements ExSystolic.PE callbacks" do
      assert function_exported?(MAC, :init, 1)
      assert function_exported?(MAC, :step, 4)
    end
  end

  describe "properties" do
    property "acc = acc + a * b for any integers" do
      check all(
              a <- integer(),
              b <- integer(),
              acc0 <- integer()
            ) do
        {new_acc, outputs} = MAC.step(acc0, %{west: a, north: b}, 0, %{})
        assert new_acc == acc0 + a * b
        assert outputs.result == acc0 + a * b
      end
    end

    property "east always equals west input when present" do
      check all(a <- integer(), b <- integer()) do
        {_, outputs} = MAC.step(0, %{west: a, north: b}, 0, %{})
        assert outputs.east == a
      end
    end

    property "south always equals north input when present" do
      check all(a <- integer(), b <- integer()) do
        {_, outputs} = MAC.step(0, %{west: a, north: b}, 0, %{})
        assert outputs.south == b
      end
    end

    property "accumulation over multiple steps is additive" do
      check all(pairs <- list_of({integer(), integer()}, max_length: 20)) do
        final_acc =
          Enum.reduce(Enum.with_index(pairs), 0, fn {{a, b}, tick}, acc ->
            {new_acc, _} = MAC.step(acc, %{west: a, north: b}, tick, %{})
            new_acc
          end)

        expected = Enum.reduce(pairs, 0, fn {a, b}, acc -> acc + a * b end)
        assert final_acc == expected
      end
    end
  end
end
