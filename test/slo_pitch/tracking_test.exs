defmodule SloPitch.TrackingTest do
  use SloPitch.DataCase, async: true

  alias SloPitch.Tracking
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
                 alignment: "middle"
               })

      assert "can't be blank" in errors_on(changeset).opponent_name
      assert "can't be blank" in errors_on(changeset).played_on
      assert "is invalid" in errors_on(changeset).status
      assert "is invalid" in errors_on(changeset).alignment
    end

    test "lists games newest first and limits recent games" do
      older = game_fixture(%{played_on: ~D[2026-04-01]})
      newer = game_fixture(%{played_on: ~D[2026-04-03]})
      newest = game_fixture(%{played_on: ~D[2026-04-05]})

      assert Tracking.list_games() |> Enum.map(& &1.id) == [newest.id, newer.id, older.id]
      assert Tracking.list_recent_games(2) |> Enum.map(& &1.id) == [newest.id, newer.id]
    end

    test "create_game/1 creates a game" do
      {:ok, game} =
        Tracking.create_game(%{
          opponent_name: "opponent",
          alignment: :home,
          played_on: Date.utc_today()
        })

      assert game.id
    end

    test "list_recent_games/1 limits results" do
      for i <- 1..10 do
        Tracking.create_game(%{
          opponent_name: "opponent",
          alignment: :home,
          played_on: Date.add(Date.utc_today(), -i)
        })
      end

      assert length(Tracking.list_recent_games(5)) == 5
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

      bench_ids = Tracking.list_bench_players(game.id) |> Enum.map(& &1.id)
      assert bench.id in bench_ids
      refute inactive.id in bench_ids
    end
  end

  describe "plate appearances and scoring" do
    test "set_game_lineup/2 replaces lineup" do
      {:ok, game} =
        Tracking.create_game(%{
          opponent_name: "opponent",
          alignment: :home,
          played_on: Date.utc_today()
        })

      {:ok, p1} = Tracking.create_player(%{name: "Player A", active: true})
      {:ok, p2} = Tracking.create_player(%{name: "Player B", active: true})

      {:ok, lineup} = Tracking.set_game_lineup(game.id, [p1.id, p2.id])

      assert length(lineup) == 2
      assert Enum.map(lineup, & &1.player_id) == [p1.id, p2.id]
    end
  end
end
