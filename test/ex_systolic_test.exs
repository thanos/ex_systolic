defmodule ExSystolicTest do
  use ExUnit.Case
  doctest ExSystolic

  test "version returns semver string" do
    assert ExSystolic.version() =~ ~r/^\d+\.\d+\.\d+$/
  end
end
