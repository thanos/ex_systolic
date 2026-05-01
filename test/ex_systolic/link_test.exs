defmodule ExSystolic.LinkTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias ExSystolic.Link

  describe "new/3" do
    test "creates a link with default latency and capacity" do
      link = Link.new({{0, 0}, :east}, {{1, 0}, :west})
      assert link.from == {{0, 0}, :east}
      assert link.to == {{1, 0}, :west}
      assert link.latency == 1
      assert link.capacity == 1
      assert Link.empty?(link)
    end

    test "creates a link with custom latency and capacity" do
      link = Link.new({{0, 0}, :east}, {{1, 0}, :west}, latency: 2, capacity: 3)
      assert link.latency == 2
      assert link.capacity == 3
    end
  end

  describe "write/2 and read/1" do
    test "write then read yields the same value" do
      link = Link.new({{0, 0}, :east}, {{1, 0}, :west})
      {:ok, link2} = Link.write(link, 42)
      {val, _link3} = Link.read(link2)
      assert val == 42
    end

    test "FIFO ordering: first in, first out" do
      link = Link.new({{0, 0}, :east}, {{1, 0}, :west}, capacity: 3)
      {:ok, l1} = Link.write(link, 1)
      {:ok, l2} = Link.write(l1, 2)
      {:ok, l3} = Link.write(l2, 3)

      {v1, l4} = Link.read(l3)
      assert v1 == 1
      {v2, l5} = Link.read(l4)
      assert v2 == 2
      {v3, _l6} = Link.read(l5)
      assert v3 == 3
    end

    test "write to full buffer returns error" do
      link = Link.new({{0, 0}, :east}, {{1, 0}, :west}, capacity: 1)
      {:ok, l1} = Link.write(link, 1)
      assert {:error, :full} = Link.write(l1, 2)
    end

    test "read from empty buffer returns :empty" do
      link = Link.new({{0, 0}, :east}, {{1, 0}, :west})
      assert {:empty, ^link} = Link.read(link)
    end
  end

  describe "peek/1" do
    test "peeks without removing" do
      link = Link.new({{0, 0}, :east}, {{1, 0}, :west}, capacity: 2)
      {:ok, l1} = Link.write(link, 10)
      assert {:ok, 10} = Link.peek(l1)
      assert Link.size(l1) == 1
    end

    test "empty buffer peek returns :empty" do
      link = Link.new({{0, 0}, :east}, {{1, 0}, :west})
      assert :empty = Link.peek(link)
    end
  end

  describe "size/1 and empty?/1" do
    test "size tracks buffer occupancy" do
      link = Link.new({{0, 0}, :east}, {{1, 0}, :west}, capacity: 5)
      assert Link.size(link) == 0

      {:ok, l1} = Link.write(link, 1)
      assert Link.size(l1) == 1

      {:ok, l2} = Link.write(l1, 2)
      assert Link.size(l2) == 2
    end

    test "empty? reflects buffer state" do
      link = Link.new({{0, 0}, :east}, {{1, 0}, :west})
      assert Link.empty?(link)

      {:ok, l1} = Link.write(link, 1)
      refute Link.empty?(l1)
    end
  end

  describe "determinism" do
    test "identical links produce identical behaviour" do
      link1 = Link.new({{0, 0}, :east}, {{1, 0}, :west})
      link2 = Link.new({{0, 0}, :east}, {{1, 0}, :west})

      {:ok, l1} = Link.write(link1, 99)
      {:ok, l2} = Link.write(link2, 99)

      {v1, _} = Link.read(l1)
      {v2, _} = Link.read(l2)
      assert v1 == v2
    end
  end

  describe "properties" do
    property "write then read always returns the written value" do
      check all value <- integer() do
        link = Link.new({{0, 0}, :east}, {{1, 0}, :west})
        {:ok, l2} = Link.write(link, value)
        {val, _} = Link.read(l2)
        assert val == value
      end
    end

    property "FIFO order holds for any sequence of writes" do
      check all values <- list_of(integer(), max_length: 5) do
        link = Link.new({{0, 0}, :east}, {{1, 0}, :west}, capacity: 10)
        filled = Enum.reduce(values, link, fn v, l ->
          {:ok, l2} = Link.write(l, v)
          l2
        end)
        {read_back, _} = Enum.reduce(values, {[], filled}, fn _, {acc, l} ->
          {v, l2} = Link.read(l)
          {acc ++ [v], l2}
        end)
        assert read_back == values
      end
    end

    property "size equals number of successful writes minus reads" do
      check all writes <- list_of(integer(), max_length: 8),
                reads_count <- integer(0..length(writes)) do
        link = Link.new({{0, 0}, :east}, {{1, 0}, :west}, capacity: 20)
        filled = Enum.reduce(writes, link, fn v, l ->
          {:ok, l2} = Link.write(l, v)
          l2
        end)
        after_reads = Enum.reduce(1..reads_count//1, filled, fn _, l ->
          {_, l2} = Link.read(l)
          l2
        end)
        assert Link.size(after_reads) == length(writes) - reads_count
      end
    end
  end
end
