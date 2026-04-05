defmodule SloPitch.GameEngine.BasesTest do
  use SloPitch.DataCase, async: true

  alias SloPitch.GameEngine.Bases

  describe "auto_destination/2" do
    test "returns correct destination base for current position and action" do
      params = [
        %{position: :batter, action: "walk", destination: :first},
        %{position: :batter, action: "single", destination: :first},
        %{position: :batter, action: "double", destination: :second},
        %{position: :batter, action: "triple", destination: :third},
        %{position: :batter, action: "out", destination: :out},
        %{position: :batter, action: "strikeout", destination: :out},
        %{position: :first, action: "walk", destination: :second},
        %{position: :first, action: "single", destination: :second},
        %{position: :first, action: "double", destination: :third},
        %{position: :first, action: "triple", destination: :home},
        %{position: :first, action: "out", destination: :first},
        %{position: :first, action: "strikeout", destination: :first},
        %{position: :second, action: "walk", destination: :third},
        %{position: :second, action: "single", destination: :third},
        %{position: :second, action: "double", destination: :home},
        %{position: :second, action: "triple", destination: :home},
        %{position: :second, action: "out", destination: :second},
        %{position: :second, action: "strikeout", destination: :second},
        %{position: :third, action: "walk", destination: :home},
        %{position: :third, action: "single", destination: :home},
        %{position: :third, action: "double", destination: :home},
        %{position: :third, action: "triple", destination: :home},
        %{position: :third, action: "out", destination: :third},
        %{position: :third, action: "strikeout", destination: :third}
      ]

      for %{position: position, action: action, destination: destination} <- params do
        assert ^destination = Bases.auto_destination(position, action)
      end
    end
  end
end
