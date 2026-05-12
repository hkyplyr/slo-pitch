defmodule SloPitch.TrackingTest do
  use SloPitch.DataCase, async: true

  alias SloPitch.Tracking

  describe "players" do
    test "lists active players first by name and toggles active state" do
      unique = System.unique_integer([:positive])
      inactive = player_fixture(%{name: "Casey #{unique}", active: false})
      active_b = player_fixture(%{name: "Blake #{unique}", active: true})
      active_a = player_fixture(%{name: "Alex #{unique}", active: true})

      assert Tracking.list_players() |> Enum.map(& &1.id) == [
               active_a.id,
               active_b.id,
               inactive.id
             ]

      assert {:ok, toggled} = Tracking.toggle_player_active(active_a)
      refute toggled.active
    end

    test "requires unique player names" do
      name = "Jordan #{System.unique_integer([:positive])}"
      player_fixture(%{name: name})

      assert {:error, changeset} =
               Tracking.create_player(%{name: name, jersey_number: 10, active: true})

      assert "has already been taken" in errors_on(changeset).name
    end

    test "validates required names and jersey number range" do
      assert {:error, changeset} =
               Tracking.create_player(%{name: "", jersey_number: -1, active: true})

      assert "can't be blank" in errors_on(changeset).name
      assert "must be greater than or equal to 0" in errors_on(changeset).jersey_number
    end
  end

  describe "games" do
    test "validates required fields, status, side, and non-negative scores" do
      assert {:error, changeset} =
               Tracking.create_game(%{
                 opponent_name: "",
                 played_on: nil,
                 status: "paused",
                 home_or_away: "middle",
                 our_score: -1
               })

      assert "can't be blank" in errors_on(changeset).opponent_name
      assert "can't be blank" in errors_on(changeset).played_on
      assert "is invalid" in errors_on(changeset).status
      assert "is invalid" in errors_on(changeset).home_or_away
      assert "must be greater than or equal to 0" in errors_on(changeset).our_score
    end

    test "lists games newest first and limits recent games" do
      older = game_fixture(%{played_on: ~D[2026-04-01]})
      newer = game_fixture(%{played_on: ~D[2026-04-03]})
      newest = game_fixture(%{played_on: ~D[2026-04-05]})

      assert Tracking.list_games() |> Enum.map(& &1.id) == [newest.id, newer.id, older.id]
      assert Tracking.list_recent_games(2) |> Enum.map(& &1.id) == [newest.id, newer.id]
    end
  end

  describe "lineups" do
    test "sets lineup order and keeps bench players to active players outside the lineup" do
      game = game_fixture()
      unique = System.unique_integer([:positive])
      player_a = player_fixture(%{name: "Alex #{unique}"})
      player_b = player_fixture(%{name: "Blake #{unique}"})
      bench = player_fixture(%{name: "Casey #{unique}"})
      inactive = player_fixture(%{name: "Devon #{unique}", active: false})

      assert {:ok, slots} = Tracking.set_game_lineup(game.id, [player_b.id, player_a.id])
      assert Enum.map(slots, & &1.player_id) == [player_b.id, player_a.id]

      assert Enum.map(Tracking.list_lineup_players(game.id), & &1.id) == [
               player_b.id,
               player_a.id
             ]

      bench_ids = Tracking.list_bench_players(game.id) |> Enum.map(& &1.id)
      assert bench.id in bench_ids
      refute inactive.id in bench_ids
    end
  end

  describe "plate appearances and scoring" do
    test "validates count consistency for walks and strikeouts" do
      game = game_fixture()
      player = player_fixture()

      assert {:error, walk_changeset} =
               Tracking.record_plate_appearance(%{
                 game_id: game.id,
                 player_id: player.id,
                 inning: 1,
                 result: "walk",
                 balls: 3
               })

      assert "must be 4 for a walk" in errors_on(walk_changeset).balls

      assert {:error, strikeout_changeset} =
               Tracking.record_plate_appearance(%{
                 game_id: game.id,
                 player_id: player.id,
                 inning: 1,
                 result: "strikeout",
                 strikes: 2
               })

      assert "must be 3 for a strikeout" in errors_on(strikeout_changeset).strikes
    end

    test "ensures innings once and upserts opponent runs and outs" do
      game = game_fixture()

      assert Tracking.ensure_innings(game.id) |> length() == 7
      assert Tracking.ensure_innings(game.id) |> length() == 7

      assert {:ok, inning} = Tracking.upsert_inning_runs(game.id, 1, %{opp_runs: 2, opp_outs: 1})
      assert inning.opp_runs == 2
      assert inning.opp_outs == 1

      assert {:ok, inning} = Tracking.upsert_inning_runs(game.id, 1, %{opp_runs: 4, opp_outs: 3})
      assert inning.opp_runs == 4
      assert inning.opp_outs == 3
    end

    test "records sequence numbers and refreshes the game score" do
      game = game_fixture()
      player = player_fixture()

      assert {:ok, first} =
               Tracking.record_plate_appearance(%{
                 game_id: game.id,
                 player_id: player.id,
                 inning: 1,
                 result: "single",
                 runs_scored: 1,
                 rbis: 1
               })

      assert {:ok, second} =
               Tracking.record_plate_appearance(%{
                 game_id: game.id,
                 player_id: player.id,
                 inning: 1,
                 result: "out",
                 runs_scored: 0,
                 rbis: 0
               })

      assert first.sequence_number == 1
      assert second.sequence_number == 2
      assert Tracking.get_game!(game.id).our_score == 1
    end

    test "resets plate appearances, inning state, score, and home run counts" do
      game = game_fixture(%{away_home_runs: 2})
      player = player_fixture()
      {:ok, _inning} = Tracking.upsert_inning_runs(game.id, 1, %{opp_runs: 3, opp_outs: 2})

      {:ok, _pa} =
        Tracking.record_plate_appearance(%{
          game_id: game.id,
          player_id: player.id,
          inning: 1,
          result: "home_run",
          runs_scored: 1,
          rbis: 1
        })

      assert {:ok, game} = Tracking.reset_game_state(game.id)
      assert game.our_score == 0
      assert game.opp_score == 0
      assert game.home_home_runs == 0
      assert game.away_home_runs == 0
      assert Tracking.list_plate_appearances(game.id) == []

      inning = Tracking.list_innings(game.id) |> List.first()
      assert inning.opp_runs == 0
      assert inning.opp_outs == 0
    end

    test "calculates player runs from explicit end bases and ignores skips" do
      game = game_fixture()
      unique = System.unique_integer([:positive])
      batter = player_fixture(%{name: "Batter #{unique}"})
      runner = player_fixture(%{name: "Runner #{unique}"})

      plate_appearance_fixture(%{
        game: game,
        player: runner,
        result: "single",
        end_bases: %{first: runner.id, second: nil, third: nil}
      })

      plate_appearance_fixture(%{
        game: game,
        player: batter,
        result: "double",
        runs_scored: 1,
        rbis: 1,
        end_bases: %{first: nil, second: batter.id, third: nil}
      })

      plate_appearance_fixture(%{game: game, player: runner, result: "out", skip: true})

      stats = Tracking.player_stats(:season)
      runner_stats = Enum.find(stats, &(&1.player_name == runner.name))
      batter_stats = Enum.find(stats, &(&1.player_name == batter.name))

      assert runner_stats.r == 1
      assert batter_stats.rbi == 1
      assert runner_stats.pa == 2
    end

    test "last five stats window excludes older games" do
      player = player_fixture()

      old_game = game_fixture(%{played_on: ~D[2026-04-01]})
      recent_games = Enum.map(2..6, &game_fixture(%{played_on: Date.add(~D[2026-04-01], &1)}))

      plate_appearance_fixture(%{
        game: old_game,
        player: player,
        result: "home_run",
        runs_scored: 1,
        rbis: 1
      })

      Enum.each(recent_games, fn game ->
        plate_appearance_fixture(%{game: game, player: player, result: "single"})
      end)

      season_stats = Tracking.player_stats(:season) |> Enum.find(&(&1.player_name == player.name))
      last5_stats = Tracking.player_stats(:last5) |> Enum.find(&(&1.player_name == player.name))

      assert season_stats.pa == 6
      assert season_stats.home_run == 1
      assert last5_stats.pa == 5
      assert last5_stats.home_run == 0
    end
  end
end
