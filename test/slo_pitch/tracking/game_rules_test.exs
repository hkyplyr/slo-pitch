defmodule SloPitch.Tracking.GameRulesTest do
  use ExUnit.Case, async: true

  alias SloPitch.Tracking.GameRules

  describe "phase rules" do
    test "away team starts on offense and moves to defense after three outs" do
      game = game(%{home_or_away: "away"})
      innings = innings()

      assert GameRules.derive_phase(game, innings, []).mode == :offense

      appearances = [
        appearance(%{result: "out"}),
        appearance(%{result: "out"}),
        appearance(%{result: "strikeout", strikes: 3})
      ]

      phase = GameRules.derive_phase(game, innings, appearances)
      assert phase.mode == :defense
      assert phase.half == :bottom
      assert phase.our_outs == 3
    end

    test "home team starts on defense and moves to offense when opponent half completes" do
      game = game(%{home_or_away: "home"})
      innings = [%{inning_number: 1, opp_runs: 2, opp_outs: 3}]

      phase = GameRules.derive_phase(game, innings, [])
      assert phase.mode == :offense
      assert phase.half == :bottom
      assert phase.opp_outs == 3
    end
  end

  describe "base advancement" do
    test "applies automatic result advancement and RBI counts" do
      bases = %{first: 1, second: 2, third: nil}

      assert {:ok, next_bases, runs, rbis} =
               GameRules.apply_result_to_bases(bases, "double", 3)

      assert next_bases == %{first: nil, second: 3, third: 1}
      assert runs == 1
      assert rbis == 1
    end

    test "custom runner plans can score runners and detect conflicts" do
      bases = %{first: 1, second: nil, third: nil}

      assert {:ok, next_bases, 1, 1} =
               GameRules.apply_result_to_bases(bases, "single", 2, %{
                 first: :home,
                 second: :auto,
                 third: :auto,
                 batter: :first
               })

      assert next_bases.first == 2

      assert {:error, :base_conflict} =
               GameRules.apply_result_to_bases(bases, "single", 2, %{
                 first: :first,
                 second: :auto,
                 third: :auto,
                 batter: :first
               })
    end

    test "derives bases from persisted appearances and ignores skipped batters" do
      appearances = [
        appearance(%{
          sequence_number: 1,
          player_id: 1,
          result: "single",
          end_bases: %{"first" => 1, "second" => nil, "third" => nil}
        }),
        appearance(%{sequence_number: 2, player_id: 2, result: "out", skip: true})
      ]

      assert GameRules.derive_bases(appearances) == %{first: 1, second: nil, third: nil}
    end
  end

  describe "home run and count rules" do
    test "enforces the home run differential cap by team side" do
      away_game = game(%{home_or_away: "away", away_home_runs: 2, home_home_runs: 0})
      home_game = game(%{home_or_away: "home", home_home_runs: 2, away_home_runs: 0})

      assert GameRules.home_run_rule_violation?(away_game, :our_team)
      assert GameRules.home_run_rule_violation?(home_game, :our_team)
      refute GameRules.home_run_rule_violation?(home_game, :opponent)
    end

    test "normalizes walk and strikeout counts" do
      assert GameRules.normalize_count_for_result("walk", 2, 3) == {4, 2}
      assert GameRules.normalize_count_for_result("strikeout", 4, 1) == {3, 3}
      assert GameRules.normalize_count_for_result("single", 2, 1) == {2, 1}
    end
  end

  defp game(attrs) do
    Map.merge(
      %{
        home_or_away: "away",
        our_score: 0,
        opp_score: 0,
        home_home_runs: 0,
        away_home_runs: 0
      },
      attrs
    )
  end

  defp innings do
    Enum.map(1..7, &%{inning_number: &1, opp_runs: 0, opp_outs: 0})
  end

  defp appearance(attrs) do
    Map.merge(
      %{
        sequence_number: 1,
        inning: 1,
        result: "out",
        player_id: 1,
        balls: 0,
        strikes: 0,
        runs_scored: 0,
        rbis: 0,
        skip: false,
        end_bases: nil
      },
      attrs
    )
  end
end
