defmodule SloPitchWeb.StatsLiveTest do
  use SloPitchWeb.ConnCase, async: true

  test "renders player stats and switches to the last five window", %{conn: conn} do
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

    {:ok, view, _html} = live(conn, ~p"/stats")

    assert has_element?(view, "#stat-row-#{String.replace(player.name, " ", "-")}")
    assert render(view) =~ ">6</td>"

    view |> element("button[phx-value-value='last5']") |> render_click()

    assert render(view) =~ ">5</td>"
  end

  test "sort controls keep stat rows rendered", %{conn: conn} do
    player_a = player_fixture()
    player_b = player_fixture()
    game = game_fixture()

    plate_appearance_fixture(%{game: game, player: player_a, result: "single"})

    plate_appearance_fixture(%{
      game: game,
      player: player_b,
      result: "home_run",
      runs_scored: 1,
      rbis: 1
    })

    {:ok, view, _html} = live(conn, ~p"/stats")

    view |> element("button[phx-value-field='rbi']") |> render_click()

    assert has_element?(view, "#stat-row-#{String.replace(player_a.name, " ", "-")}")
    assert has_element?(view, "#stat-row-#{String.replace(player_b.name, " ", "-")}")
  end
end
