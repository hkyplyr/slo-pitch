defmodule SloPitchWeb.ScoringLiveFullGameTest do
  use SloPitchWeb.ConnCase, async: true

  alias SloPitch.Tracking

  @tag :integration
  test "scores a complete seven inning game through the LiveView", %{conn: conn} do
    game = game_fixture(%{home_or_away: "away"})
    lineup_fixture(game)

    {:ok, view, _html} = live(conn, ~p"/games/#{game.id}/scoring")

    Enum.each(1..7, fn inning ->
      record_offensive_outs(view, 3)

      assert Tracking.list_plate_appearances(game.id)
             |> Enum.count(&(&1.inning == inning)) == 3

      record_defensive_outs(view, 3)
    end)

    game = Tracking.get_game!(game.id)
    assert game.status == "final"
    assert game.our_score == 0
    assert game.opp_score == 0

    assert Tracking.list_plate_appearances(game.id) |> length() == 21

    assert Tracking.list_innings(game.id)
           |> Enum.map(&{&1.inning_number, &1.opp_outs, &1.opp_runs}) == [
             {1, 3, 0},
             {2, 3, 0},
             {3, 3, 0},
             {4, 3, 0},
             {5, 3, 0},
             {6, 3, 0},
             {7, 3, 0}
           ]

    assert render(view) =~ "Game Final"
  end

  defp record_offensive_outs(view, count) do
    Enum.each(1..count, fn _ ->
      view
      |> element("button[phx-value-result='out']")
      |> render_click()
    end)
  end

  defp record_defensive_outs(view, count) do
    Enum.each(1..count, fn _ ->
      view
      |> element("button[phx-click='inc_opp_outs']")
      |> render_click()
    end)
  end
end
