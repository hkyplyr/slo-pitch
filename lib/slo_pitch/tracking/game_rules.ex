defmodule SloPitch.Tracking.GameRules do
  @moduledoc """
  Pure scoring and phase rules for a slo-pitch game.
  """

  @max_innings 7
  @destination_options [:first, :second, :third, :home, :out]

  def empty_bases, do: %{first: nil, second: nil, third: nil}

  def default_runner_plan, do: %{first: :auto, second: :auto, third: :auto, batter: :auto}

  def destination_options, do: @destination_options

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

  def derive_bases(appearances) do
    appearances
    |> Enum.sort_by(& &1.sequence_number)
    |> Enum.reduce(empty_bases(), fn appearance, bases ->
      next_bases_for_appearance(appearance, bases)
    end)
  end

  def next_bases_for_appearance(%{skip: true}, bases), do: bases

  def next_bases_for_appearance(appearance, bases) do
    case end_bases_from_record(appearance.end_bases) do
      nil ->
        case apply_result_to_bases(bases, appearance.result, appearance.player_id) do
          {:ok, next_bases, _runs, _rbis} -> next_bases
          {:error, :base_conflict} -> bases
        end

      end_bases ->
        end_bases
    end
  end

  def apply_result_to_bases(bases, result, batter_id) do
    apply_result_to_bases(bases, result, batter_id, default_runner_plan())
  end

  def apply_result_to_bases(bases, result, batter_id, runner_plan) do
    actors = [
      {:first, bases.first},
      {:second, bases.second},
      {:third, bases.third},
      {:batter, batter_id}
    ]

    case Enum.reduce_while(actors, {empty_bases(), 0}, fn actor_and_player, acc ->
           reduce_runner(actor_and_player, acc, result, runner_plan)
         end) do
      {:error, :base_conflict} ->
        {:error, :base_conflict}

      {next_bases, runs} ->
        rbis = if result == "strikeout", do: 0, else: runs
        {:ok, next_bases, runs, rbis}
    end
  end

  def default_runner_plan_for_result(result) do
    %{
      first: auto_destination(:first, result),
      second: auto_destination(:second, result),
      third: auto_destination(:third, result),
      batter: auto_destination(:batter, result)
    }
  end

  def result_requires_confirmation?(result, bases) do
    result in ["single", "double", "triple", "out"] and base_occupied?(bases)
  end

  def normalize_count_for_result("walk", _balls, strikes), do: {4, min(strikes, 2)}
  def normalize_count_for_result("strikeout", balls, _strikes), do: {min(balls, 3), 3}
  def normalize_count_for_result(_result, balls, strikes), do: {balls, strikes}

  def serialize_bases(bases), do: %{first: bases.first, second: bases.second, third: bases.third}

  def home_run_counts(game),
    do: %{home: game.home_home_runs || 0, away: game.away_home_runs || 0}

  def our_hr_increment_attrs(game, delta) do
    if game.home_or_away == "home" do
      %{home_home_runs: max((game.home_home_runs || 0) + delta, 0)}
    else
      %{away_home_runs: max((game.away_home_runs || 0) + delta, 0)}
    end
  end

  def opponent_hr_increment_attrs(game) do
    if game.home_or_away == "home" do
      %{away_home_runs: (game.away_home_runs || 0) + 1}
    else
      %{home_home_runs: (game.home_home_runs || 0) + 1}
    end
  end

  def home_run_rule_violation?(game, team) do
    counts = home_run_counts(game)

    next_counts =
      case team do
        :our_team ->
          if game.home_or_away == "home" do
            %{counts | home: counts.home + 1}
          else
            %{counts | away: counts.away + 1}
          end

        :opponent ->
          if game.home_or_away == "home" do
            %{counts | away: counts.away + 1}
          else
            %{counts | home: counts.home + 1}
          end
      end

    abs(next_counts.home - next_counts.away) > 2
  end

  def scoring_player_ids(bases, end_bases, appearance) do
    ending_ids = [end_bases.first, end_bases.second, end_bases.third]

    displaced_runners =
      [bases.third, bases.second, bases.first]
      |> Enum.reject(&(is_nil(&1) or &1 in ending_ids))

    batter_id = appearance.player_id

    scorer_candidates =
      if batter_may_score?(appearance.result) and batter_id not in ending_ids do
        displaced_runners ++ [batter_id]
      else
        displaced_runners
      end

    scorer_candidates
    |> Enum.uniq()
    |> Enum.take(max(appearance.runs_scored, 0))
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

  defp reduce_runner({_actor, nil}, {next_bases, runs}, _result, _runner_plan),
    do: {:cont, {next_bases, runs}}

  defp reduce_runner({actor, player_id}, {next_bases, runs}, result, runner_plan) do
    destination = planned_destination(actor, result, runner_plan)
    apply_runner_destination(next_bases, runs, player_id, destination)
  end

  defp apply_runner_destination(next_bases, runs, _player_id, :out),
    do: {:cont, {next_bases, runs}}

  defp apply_runner_destination(next_bases, runs, _player_id, :home),
    do: {:cont, {next_bases, runs + 1}}

  defp apply_runner_destination(next_bases, runs, player_id, destination)
       when destination in [:first, :second, :third] do
    if Map.get(next_bases, destination) do
      {:halt, {:error, :base_conflict}}
    else
      {:cont, {Map.put(next_bases, destination, player_id), runs}}
    end
  end

  defp planned_destination(actor, result, runner_plan) do
    case Map.get(runner_plan, actor, :auto) do
      :auto -> auto_destination(actor, result)
      destination -> destination
    end
  end

  defp auto_destination(:batter, "single"), do: :first
  defp auto_destination(:batter, "double"), do: :second
  defp auto_destination(:batter, "triple"), do: :third
  defp auto_destination(:batter, "home_run"), do: :home
  defp auto_destination(:batter, "walk"), do: :first
  defp auto_destination(:batter, "strikeout"), do: :out
  defp auto_destination(:batter, "out"), do: :out

  defp auto_destination(:first, "single"), do: :second
  defp auto_destination(:first, "double"), do: :third
  defp auto_destination(:first, "triple"), do: :home
  defp auto_destination(:first, "home_run"), do: :home
  defp auto_destination(:first, "walk"), do: :second
  defp auto_destination(:first, "strikeout"), do: :first
  defp auto_destination(:first, "out"), do: :first

  defp auto_destination(:second, "single"), do: :third
  defp auto_destination(:second, "double"), do: :home
  defp auto_destination(:second, "triple"), do: :home
  defp auto_destination(:second, "home_run"), do: :home
  defp auto_destination(:second, "walk"), do: :second
  defp auto_destination(:second, "strikeout"), do: :second
  defp auto_destination(:second, "out"), do: :second

  defp auto_destination(:third, "single"), do: :home
  defp auto_destination(:third, "double"), do: :home
  defp auto_destination(:third, "triple"), do: :home
  defp auto_destination(:third, "home_run"), do: :home
  defp auto_destination(:third, "walk"), do: :home
  defp auto_destination(:third, "strikeout"), do: :third
  defp auto_destination(:third, "out"), do: :third
  defp auto_destination(_actor, _result), do: :out

  defp end_bases_from_record(nil), do: nil

  defp end_bases_from_record(end_bases) do
    %{
      first: map_base(end_bases, :first),
      second: map_base(end_bases, :second),
      third: map_base(end_bases, :third)
    }
  end

  defp map_base(map, base) do
    Map.get(map, base) || Map.get(map, Atom.to_string(base))
  end

  defp base_occupied?(bases),
    do: not is_nil(bases.first) or not is_nil(bases.second) or not is_nil(bases.third)

  defp batter_may_score?(result),
    do: result in ["single", "double", "triple", "home_run", "walk"]
end
