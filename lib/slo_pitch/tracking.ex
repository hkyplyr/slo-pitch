defmodule SloPitch.Tracking do
  @moduledoc """
  Tracking context for roster, games, lineups, innings, and plate appearances.
  """

  import Ecto.Query, warn: false

  alias SloPitch.Repo
  alias SloPitch.Tracking.Game
  alias SloPitch.Tracking.GameInning
  alias SloPitch.Tracking.GameLineupSlot
  alias SloPitch.Tracking.PlateAppearance
  alias SloPitch.Tracking.Player

  def list_players do
    Player
    |> order_by([p], desc: p.active, asc: p.name)
    |> Repo.all()
  end

  def list_active_players do
    Player
    |> where([p], p.active)
    |> order_by([p], asc: p.name)
    |> Repo.all()
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
    |> Repo.preload(lineup_slots: [:player], innings: [], plate_appearances: [:player])
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

  def update_game(%Game{} = game, attrs) do
    game
    |> Game.changeset(attrs)
    |> Repo.update()
  end

  def list_lineup_slots(game_id) do
    GameLineupSlot
    |> where([s], s.game_id == ^game_id)
    |> order_by([s], asc: s.batting_order)
    |> preload([:player])
    |> Repo.all()
  end

  def list_lineup_players(game_id) do
    game_id
    |> list_lineup_slots()
    |> Enum.map(& &1.player)
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

  def list_innings(game_id) do
    GameInning
    |> where([i], i.game_id == ^game_id)
    |> order_by([i], asc: i.inning_number)
    |> Repo.all()
  end

  def upsert_inning_runs(game_id, inning_number, attrs) do
    attrs =
      attrs
      |> Map.put(:game_id, game_id)
      |> Map.put(:inning_number, inning_number)

    case Repo.get_by(GameInning, game_id: game_id, inning_number: inning_number) do
      nil ->
        %GameInning{}
        |> GameInning.changeset(attrs)
        |> Repo.insert()

      inning ->
        inning
        |> GameInning.changeset(attrs)
        |> Repo.update()
    end
  end

  def list_plate_appearances(game_id) do
    PlateAppearance
    |> where([pa], pa.game_id == ^game_id)
    |> order_by([pa], desc: pa.sequence_number)
    |> preload([:player])
    |> Repo.all()
  end

  def list_recent_plate_appearances(game_id, limit \\ 15) do
    PlateAppearance
    |> where([pa], pa.game_id == ^game_id)
    |> order_by([pa], desc: pa.sequence_number)
    |> limit(^limit)
    |> preload([:player])
    |> Repo.all()
  end

  def record_plate_appearance(attrs) do
    game_id = attrs[:game_id] || attrs.game_id
    attrs = Map.put_new(attrs, :sequence_number, next_sequence_number(game_id))

    with {:ok, plate_appearance} <-
           %PlateAppearance{}
           |> PlateAppearance.changeset(attrs)
           |> Repo.insert(),
         {:ok, _game} <- refresh_game_score(game_id) do
      {:ok, plate_appearance}
    end
  end

  def delete_latest_plate_appearance(game_id) do
    case latest_plate_appearance(game_id) do
      nil ->
        {:ok, nil}

      plate_appearance ->
        with {:ok, deleted} <- Repo.delete(plate_appearance),
             {:ok, _game} <- refresh_game_score(game_id) do
          {:ok, deleted}
        end
    end
  end

  def delete_plate_appearance(plate_appearance_id) do
    plate_appearance = Repo.get!(PlateAppearance, plate_appearance_id)

    with {:ok, deleted} <- Repo.delete(plate_appearance),
         {:ok, _game} <- refresh_game_score(plate_appearance.game_id) do
      {:ok, deleted}
    end
  end

  def reset_game_state(game_id) do
    Repo.transaction(fn ->
      Repo.delete_all(from(pa in PlateAppearance, where: pa.game_id == ^game_id))

      Repo.update_all(
        from(i in GameInning, where: i.game_id == ^game_id),
        set: [our_runs: 0, opp_runs: 0, opp_outs: 0]
      )
    end)
    |> case do
      {:ok, _result} ->
        game = Repo.get!(Game, game_id)
        {:ok, _game} = update_game(game, %{home_home_runs: 0, away_home_runs: 0})
        refresh_game_score(game_id)

      {:error, reason} ->
        {:error, reason}
    end
  end

  def next_sequence_number(nil), do: 1

  def next_sequence_number(game_id) do
    PlateAppearance
    |> where([pa], pa.game_id == ^game_id)
    |> select([pa], max(pa.sequence_number))
    |> Repo.one()
    |> case do
      nil -> 1
      sequence -> sequence + 1
    end
  end

  def latest_plate_appearance(game_id) do
    PlateAppearance
    |> where([pa], pa.game_id == ^game_id)
    |> order_by([pa], desc: pa.sequence_number)
    |> limit(1)
    |> Repo.one()
  end

  def refresh_game_score(game_id) do
    our_score =
      PlateAppearance
      |> where([pa], pa.game_id == ^game_id)
      |> select([pa], coalesce(sum(pa.runs_scored), 0))
      |> Repo.one()

    opp_score =
      GameInning
      |> where([i], i.game_id == ^game_id)
      |> select([i], coalesce(sum(i.opp_runs), 0))
      |> Repo.one()

    game = Repo.get!(Game, game_id)

    update_game(game, %{our_score: our_score, opp_score: opp_score})
  end

  def player_stats(window \\ :season) do
    game_ids =
      case window do
        :last5 -> list_recent_games(5) |> Enum.map(& &1.id)
        _ -> :all
      end

    appearances =
      PlateAppearance
      |> maybe_filter_games(game_ids)
      |> Repo.all()

    run_totals = run_totals_by_player(appearances)
    grouped = Enum.group_by(appearances, & &1.player_id)

    list_players()
    |> Enum.map(fn player ->
      pas = Map.get(grouped, player.id, [])
      walks = Enum.count(pas, &(&1.result == "walk"))
      singles = Enum.count(pas, &(&1.result == "single"))
      doubles = Enum.count(pas, &(&1.result == "double"))
      triples = Enum.count(pas, &(&1.result == "triple"))
      home_runs = Enum.count(pas, &(&1.result == "home_run"))
      strikeouts = Enum.count(pas, &(&1.result == "strikeout"))
      outs = Enum.count(pas, &(&1.result == "out"))
      hits = singles + doubles + triples + home_runs
      pa = length(pas)
      ab = max(pa - walks, 0)
      runs = Map.get(run_totals, player.id, 0)
      rbi = Enum.reduce(pas, 0, &(&1.rbis + &2))

      %{
        player_name: player.name,
        pa: pa,
        ab: ab,
        h: hits,
        single: singles,
        double: doubles,
        triple: triples,
        home_run: home_runs,
        bb: walks,
        k: strikeouts,
        out: outs,
        r: runs,
        rbi: rbi
      }
    end)
  end

  def ensure_innings(game_id, inning_count \\ 7) do
    existing =
      GameInning
      |> where([i], i.game_id == ^game_id)
      |> select([i], i.inning_number)
      |> Repo.all()

    missing = Enum.reject(1..inning_count, &(&1 in existing))

    Enum.each(missing, fn inning_number ->
      _ = upsert_inning_runs(game_id, inning_number, %{our_runs: 0, opp_runs: 0, opp_outs: 0})
    end)

    list_innings(game_id)
  end

  defp maybe_filter_games(query, :all), do: query
  defp maybe_filter_games(query, []), do: where(query, [pa], pa.game_id == -1)
  defp maybe_filter_games(query, game_ids), do: where(query, [pa], pa.game_id in ^game_ids)

  def run_totals_by_player(appearances) when is_list(appearances) do
    appearances
    |> Enum.group_by(& &1.game_id)
    |> Enum.reduce(%{}, fn {_game_id, game_appearances}, run_totals ->
      {_bases, updated_totals} =
        game_appearances
        |> Enum.sort_by(& &1.sequence_number)
        |> Enum.reduce({%{first: nil, second: nil, third: nil}, run_totals}, fn appearance,
                                                                                state ->
          accumulate_run_totals(appearance, state)
        end)

      updated_totals
    end)
  end

  defp accumulate_run_totals(appearance, {bases, totals}) do
    if appearance.skip do
      {bases, totals}
    else
      end_bases = normalized_end_bases(appearance, bases)
      scorers = scoring_players(bases, end_bases, appearance)
      updated_totals = increment_player_totals(totals, scorers)
      {end_bases, updated_totals}
    end
  end

  defp increment_player_totals(totals, scorer_ids) do
    Enum.reduce(scorer_ids, totals, fn player_id, acc ->
      Map.update(acc, player_id, 1, &(&1 + 1))
    end)
  end

  defp normalized_end_bases(appearance, bases) do
    case appearance.end_bases do
      nil ->
        fallback_end_bases(bases, appearance.result, appearance.player_id)

      end_bases ->
        %{
          first: Map.get(end_bases, :first) || Map.get(end_bases, "first"),
          second: Map.get(end_bases, :second) || Map.get(end_bases, "second"),
          third: Map.get(end_bases, :third) || Map.get(end_bases, "third")
        }
    end
  end

  defp scoring_players(bases, end_bases, appearance) do
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

  defp batter_may_score?(result), do: result in ["single", "double", "triple", "home_run", "walk"]

  defp fallback_end_bases(bases, "single", batter_id),
    do: %{first: batter_id, second: bases.first, third: bases.second}

  defp fallback_end_bases(bases, "double", batter_id),
    do: %{first: nil, second: batter_id, third: bases.first}

  defp fallback_end_bases(_bases, "triple", batter_id),
    do: %{first: nil, second: nil, third: batter_id}

  defp fallback_end_bases(_bases, "home_run", _batter_id),
    do: %{first: nil, second: nil, third: nil}

  defp fallback_end_bases(bases, "walk", batter_id) do
    first = bases.first
    second = bases.second
    third = bases.third

    {new_third, new_second, new_first} =
      if is_nil(first) do
        {third, second, batter_id}
      else
        forced_third = if is_nil(second), do: third, else: second
        {forced_third, first, batter_id}
      end

    %{first: new_first, second: new_second, third: new_third}
  end

  defp fallback_end_bases(bases, "strikeout", _batter_id), do: bases
  defp fallback_end_bases(bases, "out", _batter_id), do: bases
  defp fallback_end_bases(bases, _result, _batter_id), do: bases
end
