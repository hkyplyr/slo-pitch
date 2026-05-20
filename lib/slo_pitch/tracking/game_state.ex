defmodule SloPitch.Tracking.GameState do
  @moduledoc """
  Pure scoring and phase rules for a slo-pitch game.
  """

  alias __MODULE__
  alias SloPitch.GameEngine.Bases, as: BasesLogic
  alias SloPitch.GameEngine.Event
  alias SloPitch.Tracking.Game
  alias SloPitch.Tracking.GameState.Bases
  alias SloPitch.Tracking.GameState.Count
  alias SloPitch.Tracking.GameState.HomeRuns
  alias SloPitch.Tracking.GameState.Inning
  alias SloPitch.Tracking.GameState.PlayerStatistics
  alias SloPitch.Tracking.GameState.Score
  alias SloPitch.Tracking.Player

  @max_outs 3
  @max_runs 5
  @max_inning 7

  @type alignment :: :home | :away
  @type half :: :top | :bottom
  @type status :: :in_progress | :final

  @type t :: %__MODULE__{
          alignment: alignment(),
          game_id: integer(),
          lineup: [Player.t()],
          statistics: %{integer() => PlayerStatistics.t()},
          bases: Bases.t(),
          count: Count.t(),
          current_batter_index: non_neg_integer(),
          half: half(),
          inning: non_neg_integer(),
          innings: [Inning.t()],
          outs: non_neg_integer(),
          status: status()
        }

  defstruct [
    :alignment,
    :game_id,
    :lineup,
    :statistics,
    bases: %Bases{},
    count: %Count{},
    current_batter_index: 0,
    half: :top,
    home_runs: %HomeRuns{},
    inning: 1,
    innings: [
      %Inning{number: 1, score: %Score{}},
      %Inning{number: 2, score: %Score{}},
      %Inning{number: 3, score: %Score{}},
      %Inning{number: 4, score: %Score{}},
      %Inning{number: 5, score: %Score{}},
      %Inning{number: 6, score: %Score{}},
      %Inning{number: 7, score: %Score{}}
    ],
    outs: 0,
    status: :in_progress
  ]

  @spec init(Game.t(), [Event.t()]) :: GameState.t()
  def init(game, events) do
    game_state = %GameState{
      alignment: game.alignment,
      game_id: game.id,
      lineup: game.players,
      statistics: Map.new(game.players, &{&1.id, %PlayerStatistics{}})
    }

    Enum.reduce(events, game_state, &apply_event(&2, &1))
  end

  @doc """
  """
  @spec apply_event(GameState.t(), Event.t()) :: GameState.t()
  def apply_event(%GameState{} = state, %Event{type: :pitch, result: :strike}) do
    state =
      case Count.increment_strikes(state.count) do
        :strikeout ->
          state
          |> record_statistic(:strikeout)
          |> increment_outs(1)
          |> reset_count()
          |> next_batter()
          |> maybe_advance_half_inning()

        count ->
          %{state | count: count}
      end

    maybe_finalize_game(state)
  end

  def apply_event(state, %Event{type: :pitch, result: :ball}) do
    state =
      case Count.increment_balls(state.count) do
        :walk ->
          state
          |> record_statistic(:walk)
          |> advance_bases(:walk)
          |> reset_count()
          |> next_batter()
          |> maybe_advance_half_inning()

        count ->
          %{state | count: count}
      end

    maybe_finalize_game(state)
  end

  def apply_event(state, %Event{type: :plate_appearance, result: :skip}) do
    state
    |> next_batter()
    |> maybe_finalize_game()
  end

  def apply_event(state, %Event{type: :plate_appearance, result: result, runner_plan: runner_plan}) do
    state
    |> record_statistic(result)
    |> maybe_increment_home_runs(result)
    |> advance_bases(result, runner_plan)
    |> next_batter()
    |> maybe_advance_half_inning()
    |> maybe_finalize_game()
  end

  def apply_event(state, %Event{type: :opponent, result: :run}) do
    opponent_alignment = opponent_alignment(state)

    state
    |> increment_scores(opponent_alignment, 1)
    |> maybe_advance_half_inning()
    |> maybe_finalize_game()
  end

  def apply_event(state, %Event{type: :opponent, result: :out}) do
    state
    |> increment_outs(1)
    |> maybe_advance_half_inning()
    |> maybe_finalize_game()
  end

  def apply_event(state, %Event{type: :opponent, result: :home_run}) do
    opponent_alignment = opponent_alignment(state)

    state
    |> maybe_increment_home_runs(:home_run)
    |> increment_scores(opponent_alignment, 1)
    |> maybe_advance_half_inning()
  end

  defp record_statistic(state, statistic, player \\ nil, value \\ 1)

  defp record_statistic(state, statistic, nil, value),
    do: record_statistic(state, statistic, current_batter(state), value)

  defp record_statistic(%GameState{statistics: statistics} = state, statistic, player, value) do
    updated_statistics =
      Map.update!(statistics, player.id, &PlayerStatistics.record(&1, statistic, value))

    %{state | statistics: updated_statistics}
  end

  @type mode :: :offense | :defense
  @spec mode(GameState.t()) :: mode()
  def mode(%GameState{alignment: :away, half: :top}), do: :offense
  def mode(%GameState{alignment: :home, half: :bottom}), do: :offense
  def mode(_game_state), do: :defense

  defp maybe_increment_home_runs(%GameState{half: :top} = state, :home_run),
    do: %{state | home_runs: HomeRuns.increment_away(state.home_runs)}

  defp maybe_increment_home_runs(%GameState{half: :bottom} = state, :home_run),
    do: %{state | home_runs: HomeRuns.increment_home(state.home_runs)}

  defp maybe_increment_home_runs(state, _result), do: state

  defp increment_outs(state, outs), do: %{state | outs: min(state.outs + outs, @max_outs)}

  defp reset_count(%GameState{} = state), do: %{state | count: %Count{}}
  defp reset_bases(%GameState{} = state), do: %{state | bases: %Bases{}}
  defp reset_outs(%GameState{} = state), do: %{state | outs: 0}

  defp next_batter(%GameState{current_batter_index: current_batter_index, lineup: lineup} = state) do
    next_batter_index = rem(current_batter_index + 1, length(lineup))
    %{state | current_batter_index: next_batter_index}
  end

  defp advance_half_inning(%GameState{} = state) do
    state
    |> apply_next_half()
    |> apply_next_inning()
    |> reset_count()
    |> reset_bases()
    |> reset_outs()
  end

  defp maybe_advance_half_inning(
         %GameState{inning: @max_inning, half: :bottom, outs: @max_outs} = state
       ),
       do: state

  defp maybe_advance_half_inning(%GameState{outs: @max_outs} = state),
    do: advance_half_inning(state)

  defp maybe_advance_half_inning(%GameState{inning: @max_inning} = state), do: state

  defp maybe_advance_half_inning(%GameState{inning: inning, half: :top} = state) do
    case Enum.find(state.innings, &(&1.number == inning)) do
      %Inning{score: %Score{away: @max_runs}} -> advance_half_inning(state)
      _inning -> state
    end
  end

  defp maybe_advance_half_inning(%GameState{inning: inning, half: :bottom} = state) do
    case Enum.find(state.innings, &(&1.number == inning)) do
      %Inning{score: %Score{home: @max_runs}} -> advance_half_inning(state)
      _inning -> state
    end
  end

  defp maybe_advance_half_inning(state), do: state

  def opponent_score(%GameState{alignment: :away} = state), do: game_score(state).home
  def opponent_score(%GameState{alignment: :home} = state), do: game_score(state).away

  def current_batter(state), do: Enum.at(state.lineup, state.current_batter_index)

  defp apply_next_half(%GameState{half: :top} = state), do: %GameState{state | half: :bottom}
  defp apply_next_half(%GameState{half: :bottom} = state), do: %GameState{state | half: :top}

  defp apply_next_inning(%GameState{half: :top, inning: inning} = state),
    do: %{state | inning: inning + 1}

  defp apply_next_inning(%GameState{half: :bottom} = state), do: state

  @default_runner_plan %{first: :auto, second: :auto, third: :auto, batter: :auto}
  defp advance_bases(state, result, runner_plan \\ @default_runner_plan) do
    current_batter_id = Enum.at(state.lineup, state.current_batter_index)

    case BasesLogic.apply_result_to_bases(state.bases, result, current_batter_id, runner_plan) do
      {:ok, bases, scoring_players, out_players} ->
        total_runs = length(scoring_players)
        total_outs = length(out_players)

        %{state | bases: bases}
        |> increment_scores(state.alignment, total_runs)
        |> increment_outs(total_outs)
        |> record_statistics(:run, scoring_players)
        |> record_statistics(:out, out_players)
        |> record_statistic(:rbi, current_batter_id, total_runs)

      error ->
        error
    end
  end

  defp record_statistics(state, statistic, players),
    do: Enum.reduce(players, state, &record_statistic(&2, statistic, &1))

  defp increment_scores(state, alignment, runs) do
    %{state | innings: Inning.increment_score(state.innings, state.inning, alignment, runs)}
  end

  defp opponent_alignment(%GameState{alignment: :away}), do: :home
  defp opponent_alignment(%GameState{alignment: :home}), do: :away

  defp maybe_finalize_game(%GameState{half: :bottom, inning: @max_inning} = state) do
    %Score{home: home, away: away} = game_score(state)

    cond do
      home > away -> %{state | status: :final}
      state.outs == @max_outs -> %{state | status: :final}
      true -> state
    end
  end

  defp maybe_finalize_game(state), do: state

  def game_over?(%GameState{status: :final}), do: true
  def game_over?(_game_state), do: false

  @spec game_score(t()) :: Score.t()
  def game_score(%GameState{innings: innings}),
    do:
      Enum.reduce(
        innings,
        %Score{},
        &%{&2 | home: &2.home + &1.score.home, away: &2.away + &1.score.away}
      )
end
