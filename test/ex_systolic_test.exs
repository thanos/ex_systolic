defmodule ExSystolicTest do
  use ExUnit.Case
  doctest ExSystolic

  test "version returns semver string" do
    assert ExSystolic.version() =~ ~r/^\d+\.\d+\.\d+$/
  end

  describe "application supervision tree" do
    test "TaskSupervisor is running" do
      pid = Process.whereis(ExSystolic.TaskSupervisor)
      assert is_pid(pid)
      assert Process.alive?(pid)
    end

    test "Poolex pool :systolic_pool accepts run calls" do
      {:ok, result} =
        Poolex.run(:systolic_pool, fn _worker -> :ok end)

      assert result == :ok
    end
  end
end
