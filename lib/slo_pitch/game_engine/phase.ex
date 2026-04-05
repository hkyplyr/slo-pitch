defmodule SloPitch.GameEngine.Phase do
  @max_innings 7

  def derive_phase(game, innings, appearances) do
    inning_runs =
      appearances
      |> Enum.group_by(& &1.inning)
      |> Map.new(fn {inning, inning_appearances} ->
        outs =
          Enum.count(inning_appearances, fn pa ->
            pa.skip or pa.result in ["out", "strikeout"]
          end)

        runs = Enum.reduce(inning_appearances, 0, &(&1.runs_scored + &2))
        {inning, %{outs: outs, runs: runs}}
      end)

    inning_by_number = Map.new(innings, fn inning -> {inning.inning_number, inning} end)

    find_phase(game, inning_by_number, inning_runs, 1)
  end

  defp find_phase(game, inning_by_number, inning_runs, inning) when inning > @max_innings do
    side = game.home_or_away || "away"
    game_over_phase(side, inning_by_number, inning_runs)
  end

  defp find_phase(game, inning_by_number, inning_runs, inning) do
    side = game.home_or_away || "away"
    our = Map.get(inning_runs, inning, %{outs: 0, runs: 0})
    opp = Map.get(inning_by_number, inning, %{opp_runs: 0, opp_outs: 0})

    our_complete? = our.outs >= 3 or our.runs >= 5
    opp_complete? = opp.opp_outs >= 3 or opp.opp_runs >= 5

    case phase_decision(side, inning, our_complete?, opp_complete?, home_team_ahead?(game)) do
      {:phase, half, mode} ->
        phase_data(side, inning_by_number, inning_runs, inning, half, mode)

      :game_over ->
        game_over_phase(side, inning_by_number, inning_runs)

      :next_inning ->
        find_phase(game, inning_by_number, inning_runs, inning + 1)
    end
  end

  defp phase_decision("away", _inning, false, _opp_complete?, _home_ahead?),
    do: {:phase, :top, :offense}

  defp phase_decision("away", inning, true, _opp_complete?, true) when inning == @max_innings,
    do: :game_over

  defp phase_decision("away", _inning, true, false, _home_ahead?),
    do: {:phase, :bottom, :defense}

  defp phase_decision("away", _inning, true, true, _home_ahead?),
    do: :next_inning

  defp phase_decision("home", _inning, _our_complete?, false, _home_ahead?),
    do: {:phase, :top, :defense}

  defp phase_decision("home", inning, _our_complete?, true, true) when inning == @max_innings,
    do: :game_over

  defp phase_decision("home", _inning, false, true, _home_ahead?),
    do: {:phase, :bottom, :offense}

  defp phase_decision("home", _inning, true, true, _home_ahead?),
    do: :next_inning

  defp phase_data(side, inning_by_number, inning_runs, inning, half, mode) do
    our = Map.get(inning_runs, inning, %{outs: 0, runs: 0})
    opp = Map.get(inning_by_number, inning, %{opp_runs: 0, opp_outs: 0})

    %{
      inning: inning,
      half: half,
      mode: mode,
      side: side,
      our_outs: min(our.outs, 3),
      our_runs: our.runs,
      opp_outs: min(opp.opp_outs || 0, 3),
      opp_runs: opp.opp_runs || 0
    }
  end

  defp game_over_phase(side, inning_by_number, inning_runs) do
    phase_data(side, inning_by_number, inning_runs, @max_innings, :final, :game_over)
  end

  defp home_team_ahead?(game) do
    {home_score, away_score} =
      if game.home_or_away == "home" do
        {game.our_score, game.opp_score}
      else
        {game.opp_score, game.our_score}
      end

    home_score > away_score
  end
end
