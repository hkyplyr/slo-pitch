defmodule SloPitchWeb.ScoringLiveFullGameTest do
  use SloPitchWeb.ConnCase, async: true

  alias SloPitch.Tracking

  @tag :skip
  test "scores a complete seven inning game through the LiveView", %{conn: conn} do
    game = game_fixture(%{alignment: :away})
    lineup_fixture(game)

    {:ok, view, _html} = live(conn, ~p"/games/#{game.id}/scoring")

    Enum.each(1..7, fn _inning ->
      record_offensive_outs(view, 3)

      record_defensive_outs(view, 3)
    end)

    game = Tracking.get_game!(game.id)
    assert game.status == "final"

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
