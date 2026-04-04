defmodule SloPitchWeb.GamesLiveTest do
  use SloPitchWeb.ConnCase, async: true

  alias SloPitch.Tracking

  test "root path renders the games index", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#new-game-form")
  end

  test "creates a scheduled game from the games index", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/games")

    assert has_element?(view, "#new-game-form")

    view
    |> form("#new-game-form",
      game: %{
        opponent_name: "Prairie Heat",
        played_on: "2026-05-01",
        location: "Rotary Park",
        home_or_away: "home"
      }
    )
    |> render_submit()

    [game] = Tracking.list_games()
    assert game.opponent_name == "Prairie Heat"
    assert game.home_or_away == "home"
    assert has_element?(view, "#scheduled-game-#{game.id}")
  end

  test "does not create a game with missing required fields", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/games")

    view
    |> form("#new-game-form",
      game: %{opponent_name: " ", played_on: "", location: "", home_or_away: "away"}
    )
    |> render_submit()

    assert Tracking.list_games() == []
  end

  test "groups games by status on the index", %{conn: conn} do
    scheduled = game_fixture(%{status: "scheduled", opponent_name: "Scheduled"})
    in_progress = game_fixture(%{status: "in_progress", opponent_name: "In Progress"})
    final = game_fixture(%{status: "final", opponent_name: "Final", our_score: 8, opp_score: 4})

    {:ok, view, _html} = live(conn, ~p"/games")

    assert has_element?(view, "#scheduled-game-#{scheduled.id}")
    assert has_element?(view, "#in-progress-game-#{in_progress.id}")
    assert has_element?(view, "#recent-game-#{final.id}")
  end

  test "adds, removes, and reorders lineup players", %{conn: conn} do
    game = game_fixture()
    unique = System.unique_integer([:positive])
    player_a = player_fixture(%{name: "Alex #{unique}"})
    player_b = player_fixture(%{name: "Blake #{unique}"})

    {:ok, view, _html} = live(conn, ~p"/games/#{game.id}/setup")

    view |> element("#bench-player-#{player_a.id}") |> render_click()
    view |> element("#bench-player-#{player_b.id}") |> render_click()

    assert Tracking.list_lineup_players(game.id) |> Enum.map(& &1.id) == [
             player_a.id,
             player_b.id
           ]

    view |> element("#lineup-slot-#{player_b.id} button[phx-click='move_up']") |> render_click()

    assert Tracking.list_lineup_players(game.id) |> Enum.map(& &1.id) == [
             player_b.id,
             player_a.id
           ]

    view
    |> element("#lineup-slot-#{player_b.id} button[phx-click='remove_player']")
    |> render_click()

    assert Tracking.list_lineup_players(game.id) |> Enum.map(& &1.id) == [player_a.id]
    assert has_element?(view, "#bench-player-#{player_b.id}")
  end

  test "does not duplicate lineup players and ignores boundary moves", %{conn: conn} do
    game = game_fixture()
    player_a = player_fixture()
    player_b = player_fixture()

    {:ok, view, _html} = live(conn, ~p"/games/#{game.id}/setup")

    view |> element("#bench-player-#{player_a.id}") |> render_click()
    view |> element("#bench-player-#{player_b.id}") |> render_click()

    refute has_element?(view, "#bench-player-#{player_a.id}")

    view |> render_hook("add_player", %{"id" => Integer.to_string(player_a.id)})

    assert Tracking.list_lineup_players(game.id) |> Enum.map(& &1.id) == [
             player_a.id,
             player_b.id
           ]

    assert has_element?(view, "#lineup-slot-#{player_a.id} button[phx-click='move_up'][disabled]")

    assert Tracking.list_lineup_players(game.id) |> Enum.map(& &1.id) == [
             player_a.id,
             player_b.id
           ]

    assert has_element?(
             view,
             "#lineup-slot-#{player_b.id} button[phx-click='move_down'][disabled]"
           )

    assert Tracking.list_lineup_players(game.id) |> Enum.map(& &1.id) == [
             player_a.id,
             player_b.id
           ]
  end
end
