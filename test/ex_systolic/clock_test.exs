defmodule ExSystolic.ClockTest do
  use ExUnit.Case, async: true

  alias ExSystolic.{Array, Clock, PE.MAC}

  describe "step/1" do
    test "advances tick by one" do
      array = Array.new(rows: 1, cols: 1) |> Array.fill(MAC)
      result = Clock.step(array)
      assert result.tick == 1
    end

    test "PE receives and processes input in one step" do
      array =
        Array.new(rows: 1, cols: 1)
        |> Array.fill(MAC)
        |> Array.connect(:west_to_east)
        |> Array.connect(:north_to_south)
        |> Array.input(:west, [{{0, 0}, [3]}])
        |> Array.input(:north, [{{0, 0}, [4]}])

      result = Clock.step(array)
      {_mod, state} = result.pes[{0, 0}]
      assert state == 12
    end
  end

  describe "run/2" do
    test "runs for specified number of ticks" do
      array = Array.new(rows: 1, cols: 1) |> Array.fill(MAC)
      result = Clock.run(array, ticks: 5)
      assert result.tick == 5
    end

    test "run with ticks: 0 returns unchanged array" do
      array = Array.new(rows: 1, cols: 1) |> Array.fill(MAC)
      result = Clock.run(array, ticks: 0)
      assert result.tick == 0
    end

    test "run with backend: :partitioned delegates to Partitioned" do
      array =
        Array.new(rows: 2, cols: 2)
        |> Array.fill(MAC)
        |> Array.connect(:west_to_east)
        |> Array.connect(:north_to_south)

      interp = Clock.run(array, ticks: 2)
      part = Clock.run(array, ticks: 2, backend: :partitioned)
      assert Array.result_matrix(interp) == Array.result_matrix(part)
    end

    test "tick determinism: same inputs produce same outputs" do
      build_array = fn ->
        Array.new(rows: 2, cols: 2)
        |> Array.fill(MAC)
        |> Array.connect(:west_to_east)
        |> Array.connect(:north_to_south)
        |> Array.input(:west, [{{0, 0}, [1, 2]}, {{1, 0}, [3, 4]}])
        |> Array.input(:north, [{{0, 0}, [5, 6]}, {{0, 1}, [7, 8]}])
      end

      result1 = Clock.run(build_array.(), ticks: 5)
      result2 = Clock.run(build_array.(), ticks: 5)
      assert Array.result_matrix(result1) == Array.result_matrix(result2)
    end
  end

  describe "tick isolation" do
    test "data written in tick T is not read until tick T+1" do
      array =
        Array.new(rows: 1, cols: 2)
        |> Array.fill(MAC)
        |> Array.connect(:west_to_east)
        |> Array.connect(:north_to_south)
        |> Array.input(:west, [{{0, 0}, [5, 0]}])
        |> Array.input(:north, [{{0, 0}, [2, 0]}, {{0, 1}, [0, 3]}])
        |> Array.trace(true)

      after_tick1 = Clock.step(array)
      {_mod, state_0_0} = after_tick1.pes[{0, 0}]
      assert state_0_0 == 10

      {_mod, state_0_1} = after_tick1.pes[{0, 1}]
      assert state_0_1 == 0

      after_tick2 = Clock.step(after_tick1)
      {_mod, state_0_1_t2} = after_tick2.pes[{0, 1}]
      assert state_0_1_t2 == 15
    end

    test "PE does not read its own output from same tick" do
      array =
        Array.new(rows: 1, cols: 1)
        |> Array.fill(MAC)
        |> Array.connect(:west_to_east)
        |> Array.connect(:north_to_south)
        |> Array.input(:west, [{{0, 0}, [5]}])
        |> Array.input(:north, [{{0, 0}, [3]}])
        |> Array.trace(true)

      result = Clock.step(array)
      {_mod, state} = result.pes[{0, 0}]
      assert state == 15
    end
  end

  describe "edge cases" do
    test "inject skips when input stream is empty" do
      array =
        Array.new(rows: 1, cols: 1)
        |> Array.fill(MAC)
        |> Array.input(:west, [{{0, 0}, []}])

      result = Clock.step(array)
      assert result.tick == 1
    end

    test "inject skips when no matching link exists" do
      array =
        Array.new(rows: 1, cols: 1)
        |> Array.fill(MAC)
        |> Array.input(:west, [{{99, 99}, [10]}])

      result = Clock.step(array)
      {_mod, state} = result.pes[{0, 0}]
      assert state == 0
    end

    test "inject defers when link is already full" do
      array =
        Array.new(rows: 1, cols: 1)
        |> Array.fill(MAC)
        |> Array.connect(:west_to_east)
        |> Array.connect(:north_to_south)
        |> Array.input(:west, [{{0, 0}, [3]}])
        |> Array.input(:north, [{{0, 0}, [4]}])

      after_tick1 = Clock.step(array)

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

      result = Clock.step(pre_filled)
      remaining = result.input_streams[{{0, 0}, :west}]
      assert remaining != []
    end

    test "inject skips when input stream is empty list" do
      array =
        Array.new(rows: 1, cols: 1)
        |> Array.fill(MAC)
        |> Array.connect(:west_to_east)
        |> Array.connect(:north_to_south)
        |> Array.input(:west, [{{0, 0}, []}])

      result = Clock.step(array)
      {_mod, state} = result.pes[{0, 0}]
      assert state == 0
    end
  end

  describe "trace recording" do
    test "trace is recorded when enabled" do
      array =
        Array.new(rows: 1, cols: 1)
        |> Array.fill(MAC)
        |> Array.connect(:west_to_east)
        |> Array.connect(:north_to_south)
        |> Array.input(:west, [{{0, 0}, [2]}])
        |> Array.input(:north, [{{0, 0}, [3]}])
        |> Array.trace(true)

      result = Clock.step(array)
      assert length(result.trace.events) == 1
      event = hd(result.trace.events)
      assert event.tick == 0
      assert event.coord == {0, 0}
      assert event.state_before == 0
      assert event.state_after == 6
    end

    test "no trace when disabled" do
      array =
        Array.new(rows: 1, cols: 1)
        |> Array.fill(MAC)
        |> Array.trace(false)

      result = Clock.step(array)
      assert result.trace.events == []
    end
  end
end
