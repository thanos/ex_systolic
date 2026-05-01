defmodule ExSystolic.TraceTest do
  use ExUnit.Case, async: true

  alias ExSystolic.Trace
  alias ExSystolic.Trace.Event

  describe "new/1" do
    test "creates empty trace" do
      trace = Trace.new()
      assert trace.events == []
    end

    test "creates trace with initial events" do
      event = %Event{
        tick: 0,
        coord: {0, 0},
        inputs: %{},
        outputs: %{},
        state_before: 0,
        state_after: 0
      }

      trace = Trace.new([event])
      assert length(trace.events) == 1
    end
  end

  describe "record/2" do
    test "appends event to trace" do
      trace = Trace.new()

      event = %Event{
        tick: 0,
        coord: {0, 0},
        inputs: %{west: 3},
        outputs: %{result: 12},
        state_before: 0,
        state_after: 12
      }

      trace2 = Trace.record(trace, event)
      assert length(trace2.events) == 1
      assert hd(trace2.events).tick == 0
    end

    test "events are ordered by recording order" do
      trace = Trace.new()

      e0 = %Event{
        tick: 0,
        coord: {0, 0},
        inputs: %{},
        outputs: %{},
        state_before: 0,
        state_after: 0
      }

      e1 = %Event{
        tick: 1,
        coord: {0, 0},
        inputs: %{},
        outputs: %{},
        state_before: 0,
        state_after: 0
      }

      trace2 = trace |> Trace.record(e0) |> Trace.record(e1)
      assert [0, 1] = Enum.map(trace2.events, & &1.tick)
    end
  end

  describe "at/2" do
    test "filters by tick" do
      e0 = %Event{
        tick: 0,
        coord: {0, 0},
        inputs: %{},
        outputs: %{},
        state_before: 0,
        state_after: 0
      }

      e1 = %Event{
        tick: 1,
        coord: {0, 0},
        inputs: %{},
        outputs: %{},
        state_before: 0,
        state_after: 0
      }

      e2 = %Event{
        tick: 1,
        coord: {1, 0},
        inputs: %{},
        outputs: %{},
        state_before: 0,
        state_after: 0
      }

      trace = Trace.new([e0, e1, e2])
      assert [_e0] = Trace.at(trace, 0)
      assert [_e0, _e1] = Trace.at(trace, 1)
      assert [] = Trace.at(trace, 5)
    end
  end

  describe "for_coord/2" do
    test "filters by coordinate" do
      e0 = %Event{
        tick: 0,
        coord: {0, 0},
        inputs: %{},
        outputs: %{},
        state_before: 0,
        state_after: 0
      }

      e1 = %Event{
        tick: 1,
        coord: {0, 0},
        inputs: %{},
        outputs: %{},
        state_before: 0,
        state_after: 0
      }

      e2 = %Event{
        tick: 0,
        coord: {1, 1},
        inputs: %{},
        outputs: %{},
        state_before: 0,
        state_after: 0
      }

      trace = Trace.new([e0, e1, e2])
      assert length(Trace.for_coord(trace, {0, 0})) == 2
      assert length(Trace.for_coord(trace, {1, 1})) == 1
    end
  end
end
