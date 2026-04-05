defmodule SloPitch.TrackingTest do
  use SloPitch.DataCase, async: true

  alias SloPitch.Tracking
  alias SloPitch.Tracking.PlateAppearance
  alias SloPitch.Tracking.Player

  describe "players" do
    test "create_player/1 creates a player" do
      assert {:ok, %Player{} = player} =
               Tracking.create_player(%{name: "Travis", active: true})

      assert player.name == "Travis"
      assert player.active == true
    end

    test "list_players/0 orders active first, then by name" do
      {:ok, _} = Tracking.create_player(%{name: "Player B", active: false})
      {:ok, _} = Tracking.create_player(%{name: "Player A", active: true})

      [first | _] = Tracking.list_players()
      assert first.name == "Player A"
    end

    test "toggle_player_active/1 flips active flag" do
      {:ok, player} = Tracking.create_player(%{name: "Test", active: true})

      {:ok, updated} = Tracking.toggle_player_active(player)
      assert updated.active == false
    end
  end

  describe "games" do
    test "create_game/1 creates a game" do
      {:ok, game} =
        Tracking.create_game(%{
          opponent_name: "opponent",
          played_on: Date.utc_today(),
          our_score: 0,
          opp_score: 0
        })

      assert game.id
    end

    test "list_recent_games/1 limits results" do
      for i <- 1..10 do
        Tracking.create_game(%{
          opponent_name: "opponent",
          played_on: Date.add(Date.utc_today(), -i),
          our_score: 0,
          opp_score: 0
        })
      end

      assert length(Tracking.list_recent_games(5)) == 5
    end
  end

  describe "sequence numbers" do
    test "next_sequence_number/1 returns 1 when no appearances" do
      assert Tracking.next_sequence_number(123) == 1
    end

    test "next_sequence_number/1 increments correctly" do
      {:ok, game} =
        Tracking.create_game(%{
          opponent_name: "opponent",
          played_on: Date.utc_today(),
          our_score: 0,
          opp_score: 0
        })

      {:ok, player} = Tracking.create_player(%{name: "Player", active: true})

      {:ok, _} =
        Tracking.record_plate_appearance(%{
          inning: 1,
          game_id: game.id,
          player_id: player.id,
          result: "single",
          runs_scored: 0,
          rbis: 0
        })

      assert Tracking.next_sequence_number(game.id) == 2
    end
  end

  describe "lineups" do
    test "set_game_lineup/2 replaces lineup" do
      {:ok, game} =
        Tracking.create_game(%{
          opponent_name: "opponent",
          played_on: Date.utc_today(),
          our_score: 0,
          opp_score: 0
        })

      {:ok, p1} = Tracking.create_player(%{name: "Player A", active: true})
      {:ok, p2} = Tracking.create_player(%{name: "Player B", active: true})

      {:ok, lineup} = Tracking.set_game_lineup(game.id, [p1.id, p2.id])

      assert length(lineup) == 2
      assert Enum.map(lineup, & &1.player_id) == [p1.id, p2.id]
    end
  end

  describe "innings" do
    test "upsert_inning_runs inserts and updates" do
      {:ok, game} =
        Tracking.create_game(%{
          opponent_name: "opponent",
          played_on: Date.utc_today(),
          our_score: 0,
          opp_score: 0
        })

      {:ok, inning} =
        Tracking.upsert_inning_runs(game.id, 1, %{our_runs: 1, opp_runs: 0, opp_outs: 0})

      assert inning.our_runs == 1

      {:ok, updated} =
        Tracking.upsert_inning_runs(game.id, 1, %{our_runs: 3, opp_runs: 0, opp_outs: 0})

      assert updated.our_runs == 3
    end

    test "ensure_innings creates missing innings" do
      {:ok, game} =
        Tracking.create_game(%{
          opponent_name: "opponent",
          played_on: Date.utc_today(),
          our_score: 0,
          opp_score: 0
        })

      innings = Tracking.ensure_innings(game.id, 3)
      assert length(innings) == 3
    end
  end

  describe "plate appearances" do
    test "record_plate_appearance inserts and updates score" do
      {:ok, game} =
        Tracking.create_game(%{
          opponent_name: "opponent",
          played_on: Date.utc_today(),
          our_score: 0,
          opp_score: 0
        })

      {:ok, player} = Tracking.create_player(%{name: "Player", active: true})

      {:ok, pa} =
        Tracking.record_plate_appearance(%{
          inning: 1,
          game_id: game.id,
          player_id: player.id,
          result: "home_run",
          runs_scored: 1,
          rbis: 1
        })

      assert pa.sequence_number == 1

      game = Tracking.get_game!(game.id)
      assert game.our_score == 1
    end

    test "delete_latest_plate_appearance removes most recent" do
      {:ok, game} =
        Tracking.create_game(%{
          opponent_name: "opponent",
          played_on: Date.utc_today(),
          our_score: 0,
          opp_score: 0
        })

      {:ok, player} = Tracking.create_player(%{name: "Player", active: true})

      {:ok, _} =
        Tracking.record_plate_appearance(%{
          inning: 1,
          game_id: game.id,
          player_id: player.id,
          result: "single",
          runs_scored: 0,
          rbis: 0
        })

      {:ok, deleted} = Tracking.delete_latest_plate_appearance(game.id)
      assert deleted
      assert Tracking.latest_plate_appearance(game.id) == nil
    end
  end

  describe "run_totals_by_player/1" do
    test "counts runs scored correctly across appearances" do
      {:ok, player1} = Tracking.create_player(%{name: "Player A", active: true})
      {:ok, player2} = Tracking.create_player(%{name: "Player B", active: true})

      appearances = [
        %PlateAppearance{
          game_id: 1,
          sequence_number: 1,
          player_id: player1.id,
          result: "single",
          runs_scored: 0,
          rbis: 0,
          skip: false,
          end_bases: %{first: player1.id}
        },
        %PlateAppearance{
          game_id: 1,
          sequence_number: 2,
          player_id: player2.id,
          result: "home_run",
          runs_scored: 2,
          rbis: 2,
          skip: false,
          end_bases: %{first: nil, second: nil, third: nil}
        }
      ]

      totals = Tracking.run_totals_by_player(appearances)

      assert totals[player1.id] == 1
      assert totals[player2.id] == 1
    end
  end

  describe "player_stats/1" do
    test "returns stats per player" do
      {:ok, game} =
        Tracking.create_game(%{
          opponent_name: "opponent",
          played_on: Date.utc_today(),
          our_score: 0,
          opp_score: 0
        })

      {:ok, player} = Tracking.create_player(%{name: "Stat Guy", active: true})

      {:ok, _} =
        Tracking.record_plate_appearance(%{
          inning: 1,
          game_id: game.id,
          player_id: player.id,
          result: "single",
          runs_scored: 0,
          rbis: 0
        })

      [stats] = Tracking.player_stats()

      assert stats.player_name == "Stat Guy"
      assert stats.h == 1
      assert stats.pa == 1
    end
  end
end
