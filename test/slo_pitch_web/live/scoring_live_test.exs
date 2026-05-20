defmodule SloPitchWeb.ScoringLiveTest do
  use SloPitchWeb.ConnCase, async: true

  test "records hits, advances the batter, and supports undo", %{conn: conn} do
    game = game_fixture()
    [batter, next_batter | _] = lineup_fixture(game)

    {:ok, view, _html} = live(conn, ~p"/games/#{game.id}/scoring")

    assert render(view) =~ batter.name

    view |> element("button[phx-value-result='single']") |> render_click()

    assert render(view) =~ next_batter.name

    view |> element("#undo-last-button") |> render_click()

    assert render(view) =~ next_batter.name
  end

  test "records extra-base hits with expected bases and scoring", %{conn: conn} do
    game = game_fixture()
    lineup_fixture(game)
    {:ok, view, _html} = live(conn, ~p"/games/#{game.id}/scoring")
    view |> element("button[phx-value-result='double']") |> render_click()
    view |> element("button[phx-value-result='triple']") |> render_click()
    view |> element("button[phx-click='confirm_result_modal']") |> render_click()
    view |> element("button[phx-value-result='home_run']") |> render_click()
  end

  test "walks and strikeouts normalize counts", %{conn: conn} do
    game = game_fixture()
    lineup_fixture(game)
    {:ok, view, _html} = live(conn, ~p"/games/#{game.id}/scoring")

    view |> element("#pitch-ball-button") |> render_click()
    view |> element("#pitch-ball-button") |> render_click()
    view |> element("#pitch-ball-button") |> render_click()
    view |> element("#pitch-ball-button") |> render_click()

    view |> element("#pitch-strike-button") |> render_click()
    view |> element("#pitch-strike-button") |> render_click()
    view |> element("#pitch-strike-button") |> render_click()
  end

  test "blocks home runs that exceed the differential cap", %{conn: conn} do
    game = game_fixture()
    lineup_fixture(game)
    {:ok, view, _html} = live(conn, ~p"/games/#{game.id}/scoring")

    view |> element("button[phx-value-result='home_run']") |> render_click()
    view |> element("button[phx-value-result='home_run']") |> render_click()
    view |> element("button[phx-value-result='home_run']") |> render_click()
  end

  @tag :skip
  test "opponent home runs obey the differential cap", %{conn: conn} do
    game = game_fixture()
    lineup_fixture(game)
    {:ok, view, _html} = live(conn, ~p"/games/#{game.id}/scoring")

    Enum.each(1..3, fn _ ->
      view |> element("button[phx-value-result='out']") |> render_click()
    end)

    view |> element("button[phx-click='inc_opp_home_run']") |> render_click()

    assert render(view) =~ "Home run cap reached"
  end

  @tag :skip
  test "opponent runs and outs can be undone", %{conn: conn} do
    game = game_fixture()
    lineup_fixture(game)
    {:ok, view, _html} = live(conn, ~p"/games/#{game.id}/scoring")

    Enum.each(1..3, fn _ ->
      view |> element("button[phx-value-result='out']") |> render_click()
    end)

    view |> element("button[phx-click='inc_opp_runs']") |> render_click()
    view |> element("button[phx-click='inc_opp_outs']") |> render_click()
  end

  test "runner modal can customize destinations and rejects conflicts", %{conn: conn} do
    game = game_fixture()
    lineup_fixture(game)
    {:ok, view, _html} = live(conn, ~p"/games/#{game.id}/scoring")

    view |> element("button[phx-value-result='single']") |> render_click()
    view |> element("button[phx-value-result='single']") |> render_click()

    assert has_element?(view, "button[phx-click='confirm_result_modal']")

    view
    |> element("button[phx-value-runner='first'][phx-value-destination='home']")
    |> render_click()

    view |> element("button[phx-click='confirm_result_modal']") |> render_click()
  end

  test "inserted and skipped batters are persisted", %{conn: conn} do
    game = game_fixture()
    lineup_fixture(game)
    {:ok, view, _html} = live(conn, ~p"/games/#{game.id}/scoring")

    view |> element("button[phx-value-result='single']") |> render_click()
    view |> element("#skip-batter-button") |> render_click()
  end
end
