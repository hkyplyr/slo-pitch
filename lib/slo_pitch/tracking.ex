defmodule SloPitch.Tracking do
  @moduledoc """
  Tracking context for roster, games, lineups, innings, and plate appearances.
  """

  import Ecto.Query, warn: false

  alias SloPitch.GameEngine.Event
  alias SloPitch.Repo
  alias SloPitch.Tracking.Game
  alias SloPitch.Tracking.GameLineupSlot
  alias SloPitch.Tracking.Player

  def list_players do
    Player
    |> order_by([p], desc: p.active, asc: p.name)
    |> Repo.all()
  end

  def get_events(game_id) do
    Event
    |> where([e], e.game_id == ^game_id)
    |> order_by([e], asc: e.inserted_at)
    |> Repo.all()
  end

  def undo_event(game_id) do
    Event
    |> where([e], e.game_id == ^game_id)
    |> order_by(desc: :inserted_at)
    |> limit(1)
    |> Repo.one!()
    |> Repo.delete!()
  end

  def create_player(attrs) do
    %Player{}
    |> Player.changeset(attrs)
    |> Repo.insert()
  end

  def toggle_player_active(%Player{} = player) do
    update_player(player, %{active: !player.active})
  end

  def update_player(%Player{} = player, attrs) do
    player
    |> Player.changeset(attrs)
    |> Repo.update()
  end

  def get_game!(id) do
    Game
    |> Repo.get!(id)
    |> Repo.preload(:players)
  end

  def list_games do
    Game
    |> order_by([g], desc: g.played_on)
    |> Repo.all()
  end

  def list_recent_games(limit \\ 5) do
    Game
    |> order_by([g], desc: g.played_on)
    |> limit(^limit)
    |> Repo.all()
  end

  def create_game(attrs) do
    %Game{}
    |> Game.changeset(attrs)
    |> Repo.insert()
  end

  def list_lineup_slots(game_id) do
    GameLineupSlot
    |> where([s], s.game_id == ^game_id)
    |> order_by([s], asc: s.batting_order)
    |> preload([:player])
    |> Repo.all()
  end

  def list_bench_players(game_id) do
    lineup_player_ids =
      GameLineupSlot
      |> where([s], s.game_id == ^game_id)
      |> select([s], s.player_id)
      |> Repo.all()

    Player
    |> where([p], p.active)
    |> where([p], p.id not in ^lineup_player_ids)
    |> order_by([p], asc: p.name)
    |> Repo.all()
  end

  def set_game_lineup(game_id, player_ids) when is_list(player_ids) do
    timestamp = DateTime.utc_now() |> DateTime.truncate(:second)

    rows =
      player_ids
      |> Enum.with_index(1)
      |> Enum.map(fn {player_id, order} ->
        %{
          game_id: game_id,
          player_id: player_id,
          batting_order: order,
          starter: true,
          inserted_at: timestamp,
          updated_at: timestamp
        }
      end)

    Repo.transaction(fn ->
      Repo.delete_all(from(s in GameLineupSlot, where: s.game_id == ^game_id))
      Repo.insert_all(GameLineupSlot, rows)
    end)
    |> case do
      {:ok, _result} -> {:ok, list_lineup_slots(game_id)}
      {:error, reason} -> {:error, reason}
    end
  end
end
