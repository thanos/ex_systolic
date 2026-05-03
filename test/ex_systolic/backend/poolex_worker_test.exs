defmodule ExSystolic.Backend.PoolexWorkerTest do
  use ExUnit.Case, async: true

  alias ExSystolic.Backend.PoolexWorker
  alias ExSystolic.PE.MAC

  describe "start_link/0" do
    test "starts a linked GenServer" do
      {:ok, pid} = PoolexWorker.start_link()
      assert is_pid(pid)
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end
  end

  describe "handle_call {:run_tile, ...}" do
    test "executes tile PE step and returns result" do
      {:ok, pid} = PoolexWorker.start_link()

      pes = %{{0, 0} => {MAC, 0}}
      inputs = %{{{0, 0}, :west} => 3, {{0, 0}, :north} => 4}

      result =
        GenServer.call(pid, {:run_tile, pes, inputs, 0, true})

      {new_pes, outputs, events} = result
      assert elem(new_pes[{0, 0}], 1) == 12
      assert outputs[{0, 0}].result == 12
      assert length(events) == 1

      GenServer.stop(pid)
    end

    test "trace disabled produces no events" do
      {:ok, pid} = PoolexWorker.start_link()

      pes = %{{0, 0} => {MAC, 0}}
      inputs = %{{{0, 0}, :west} => 3, {{0, 0}, :north} => 4}

      {_, _, events} =
        GenServer.call(pid, {:run_tile, pes, inputs, 0, false})

      assert events == []

      GenServer.stop(pid)
    end
  end
end
