defmodule SloPitch.Tracking.Games do
  @moduledoc """
  TODO - add moduledoc
  """

  import Ecto.Query

  alias SloPitch.GameEngine.Event
  alias SloPitch.GameEngine.Event.RunnerPlan
  alias SloPitch.Repo
  alias SloPitch.Tracking
  alias SloPitch.Tracking.Game
  alias SloPitch.Tracking.GameState

  @spec record_pitch(integer(), GameState.t(), Event.pitch_result()) :: GameState.t()
  def record_pitch(game_id, game_state, result) do
    event =
      record_event(%{
        type: :pitch,
        result: result,
        game_id: game_id,
        player_id: GameState.current_batter(game_state).id
      })

    GameState.apply_event(game_state, event)
  end

  @spec record_plate_appearance(
          integer(),
          GameState.t(),
          Event.plate_appearance_result(),
          RunnerPlan.t()
        ) :: GameState.t()
  def record_plate_appearance(game_id, game_state, result, runner_plan) do
    event =
      record_event(%{
        type: :plate_appearance,
        result: result,
        runner_plan: runner_plan,
        game_id: game_id,
        player_id: GameState.current_batter(game_state).id
      })

    GameState.apply_event(game_state, event)
  end

  @spec record_opponent(integer(), GameState.t(), Event.opponent_result()) :: GameState.t()
  def record_opponent(game_id, game_state, result) do
    event =
      record_event(%{
        type: :opponent,
        result: result,
        game_id: game_id
      })

    GameState.apply_event(game_state, event)
  end

  @spec undo_last_event(Game.t()) :: GameState.t()
  def undo_last_event(%{id: game_id} = game) do
    Event
    |> where([e], e.game_id == ^game_id)
    |> order_by(desc: :inserted_at)
    |> limit(1)
    |> Repo.one!()
    |> Repo.delete!()

    rebuild_game_state(game)
  end

  @spec rebuild_game_state(Game.t() | integer()) :: GameState.t()
  def rebuild_game_state(game_id) when is_integer(game_id) do
    game_id
    |> Tracking.get_game!()
    |> rebuild_game_state()
  end

  def rebuild_game_state(game) do
    events = Tracking.get_events(game.id)
    GameState.init(game, events)
  end

  defp record_event(attrs) do
    attrs
    |> Event.changeset()
    |> Repo.insert!()
  end
end
