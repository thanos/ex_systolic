defmodule ExSystolic.Backend.InterpretedTest do
  use ExUnit.Case, async: true

  alias ExSystolic.Backend.Interpreted
  alias ExSystolic.{Link, PE.MAC}

  describe "execute_tick/4" do
    test "executes one PE step" do
      pes = %{{0, 0} => {MAC, 0}}
      inputs = %{{{0, 0}, :west} => 3, {{0, 0}, :north} => 4}
      {new_pes, outputs, events} = Interpreted.execute_tick(pes, inputs, 0, true)

      assert elem(new_pes[{0, 0}], 1) == 12
      assert outputs[{0, 0}].result == 12
      assert length(events) == 1
    end

    test "trace disabled produces no events" do
      pes = %{{0, 0} => {MAC, 0}}
      inputs = %{{{0, 0}, :west} => 3, {{0, 0}, :north} => 4}
      {_, _, events} = Interpreted.execute_tick(pes, inputs, 0, false)
      assert events == []
    end

    test "multiple PEs" do
      pes = %{{0, 0} => {MAC, 0}, {0, 1} => {MAC, 0}}

      inputs = %{
        {{0, 0}, :west} => 2,
        {{0, 0}, :north} => 3,
        {{0, 1}, :west} => 5,
        {{0, 1}, :north} => 7
      }

      {new_pes, _outputs, _events} = Interpreted.execute_tick(pes, inputs, 0, false)

      assert elem(new_pes[{0, 0}], 1) == 6
      assert elem(new_pes[{0, 1}], 1) == 35
    end
  end

  describe "write_outputs/3" do
    test "writes PE outputs to links" do
      link = Link.new({{0, 0}, :east}, {{0, 1}, :west})
      outputs = %{{0, 0} => %{east: 99, result: 99}}
      {new_links, _remaining} = Interpreted.write_outputs([link], outputs, %{})
      {:ok, val} = Link.peek(Enum.at(new_links, 0))
      assert val == 99
    end

    test "silently drops output when link is full" do
      link = Link.new({{0, 0}, :east}, {{0, 1}, :west}, capacity: 1)
      {:ok, full_link} = Link.write(link, 42)
      outputs = %{{0, 0} => %{east: 99}}
      {new_links, _remaining} = Interpreted.write_outputs([full_link], outputs, %{})
      {:ok, val} = Link.peek(Enum.at(new_links, 0))
      assert val == 42
    end

    test "silently skips output port with no matching link" do
      link = Link.new({{0, 0}, :east}, {{0, 1}, :west})
      outputs = %{{0, 0} => %{north: 77, result: 77}}
      {new_links, _remaining} = Interpreted.write_outputs([link], outputs, %{})
      assert Link.empty?(Enum.at(new_links, 0))
    end

    test "injects external input streams" do
      link = Link.new({{-1, 0}, :east}, {{0, 0}, :west})
      input_streams = %{{{0, 0}, :west} => [10, 20]}
      {new_links, remaining} = Interpreted.write_outputs([link], %{}, input_streams)
      {:ok, val} = Link.peek(Enum.at(new_links, 0))
      assert val == 10
      assert remaining[{{0, 0}, :west}] == [20]
    end

    test "inject input with exhausted stream removes key" do
      link = Link.new({{-1, 0}, :east}, {{0, 0}, :west})
      input_streams = %{{{0, 0}, :west} => [10]}
      {new_links, remaining} = Interpreted.write_outputs([link], %{}, input_streams)
      {:ok, val} = Link.peek(Enum.at(new_links, 0))
      assert val == 10
      refute Map.has_key?(remaining, {{0, 0}, :west})
    end

    test "inject input with no matching link silently drops stream" do
      input_streams = %{{{99, 99}, :west} => [10]}
      {new_links, remaining} = Interpreted.write_outputs([], %{}, input_streams)
      assert new_links == []
      assert remaining == %{}
    end

    test "inject input deferred when link is full" do
      link = Link.new({{-1, 0}, :east}, {{0, 0}, :west}, capacity: 1)
      {:ok, full_link} = Link.write(link, 42)
      input_streams = %{{{0, 0}, :west} => [99, 100]}
      {new_links, remaining} = Interpreted.write_outputs([full_link], %{}, input_streams)
      {:ok, val} = Link.peek(Enum.at(new_links, 0))
      assert val == 42
      assert remaining[{{0, 0}, :west}] == [99, 100]
    end

    test "inject with empty stream is a no-op" do
      link = Link.new({{-1, 0}, :east}, {{0, 0}, :west})
      input_streams = %{{{0, 0}, :west} => []}
      {new_links, remaining} = Interpreted.write_outputs([link], %{}, input_streams)
      assert Link.empty?(Enum.at(new_links, 0))
      assert remaining == %{}
    end
  end

  describe "collect_results/1" do
    test "collects final states" do
      pes = %{{0, 0} => {MAC, 42}, {1, 1} => {MAC, 7}}
      results = Interpreted.collect_results(pes)
      assert results[{0, 0}] == 42
      assert results[{1, 1}] == 7
    end
  end
end
