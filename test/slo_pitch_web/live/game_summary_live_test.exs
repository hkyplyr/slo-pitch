defmodule SloPitchWeb.GameSummaryLiveTest do
  use SloPitchWeb.ConnCase, async: true

  alias SloPitch.Tracking

  test "renders line score and batting lines from tracked game data", %{conn: conn} do
    game = game_fixture(%{opponent_name: "Prairie Heat"})
    player = player_fixture()

    {:ok, _inning} = Tracking.upsert_inning_runs(game.id, 1, %{opp_runs: 2})

    plate_appearance_fixture(%{
      game: game,
      player: player,
      result: "home_run",
      runs_scored: 1,
      rbis: 1
    })

    {:ok, view, _html} = live(conn, ~p"/games/#{game.id}")

    assert has_element?(view, "#line-score-away")
    assert has_element?(view, "#line-score-home")
    assert has_element?(view, "#batting-line-#{String.replace(player.name, " ", "-")}")
  end
end
