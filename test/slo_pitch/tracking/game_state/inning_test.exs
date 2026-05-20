defmodule SloPitch.Tracking.GameState.InningTest do
  use SloPitch.DataCase, async: true

  alias SloPitch.Tracking.GameState.Inning
  alias SloPitch.Tracking.GameState.Score

  describe "increment_score/4" do
    test "updates score in specific inning for home team" do
      assert [
               %Inning{number: 1, score: %Score{home: 0, away: 0}},
               %Inning{number: 2, score: %Score{home: 0, away: 0}},
               %Inning{number: 3, score: %Score{home: 0, away: 0}},
               %Inning{number: 4, score: %Score{home: 1, away: 0}},
               %Inning{number: 5, score: %Score{home: 0, away: 0}},
               %Inning{number: 6, score: %Score{home: 0, away: 0}},
               %Inning{number: 7, score: %Score{home: 0, away: 0}}
             ] = Inning.increment_score(innings(), 4, :home, 1)
    end

    test "updates score in specific inning for away team" do
      assert [
               %Inning{number: 1, score: %Score{home: 0, away: 4}},
               %Inning{number: 2, score: %Score{home: 0, away: 0}},
               %Inning{number: 3, score: %Score{home: 0, away: 0}},
               %Inning{number: 4, score: %Score{home: 0, away: 0}},
               %Inning{number: 5, score: %Score{home: 0, away: 0}},
               %Inning{number: 6, score: %Score{home: 0, away: 0}},
               %Inning{number: 7, score: %Score{home: 0, away: 0}}
             ] = Inning.increment_score(innings(), 1, :away, 4)
    end

    test "cannot exceed 5 runs for a score" do
      assert [%Inning{number: 1, score: %Score{home: 5}}] =
               Inning.increment_score([%Inning{number: 1}], 1, :home, 6)
    end
  end

  defp innings, do: Enum.map(1..7, &%Inning{number: &1})
end
