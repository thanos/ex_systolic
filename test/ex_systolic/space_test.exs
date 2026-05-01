defmodule ExSystolic.SpaceTest do
  use ExUnit.Case, async: true

  alias ExSystolic.Space
  alias ExSystolic.Space.Grid2D

  describe "behaviour exports" do
    test "Grid2D implements the Space behaviour" do
      behaviours =
        Grid2D.__info__(:attributes)
        |> Keyword.get_values(:behaviour)
        |> List.flatten()

      assert Space in behaviours
    end

    test "Space module defines the expected callbacks" do
      callbacks = Space.behaviour_info(:callbacks)
      assert {:normalize, 1} in callbacks
      assert {:neighbors, 2} in callbacks
      assert {:ports, 2} in callbacks
    end
  end
end
