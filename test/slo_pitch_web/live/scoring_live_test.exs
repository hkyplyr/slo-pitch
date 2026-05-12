defmodule SloPitchWeb.ScoringLiveTest do
  use SloPitchWeb.ConnCase, async: true

  alias SloPitch.Tracking

  test "shows an empty state instead of crashing when a game has no lineup", %{conn: conn} do
    game = game_fixture()

    {:ok, view, _html} = live(conn, ~p"/games/#{game.id}/scoring")

    assert has_element?(view, "#scoring-empty-lineup")
    assert has_element?(view, "#skip-batter-button[disabled]")
    assert has_element?(view, "#insert-batter-button[disabled]")
  end

  test "records hits, advances the batter, and supports undo", %{conn: conn} do
    game = game_fixture()
    [batter, next_batter | _] = lineup_fixture(game)

    {:ok, view, _html} = live(conn, ~p"/games/#{game.id}/scoring")

    assert render(view) =~ batter.name

    view |> element("button[phx-value-result='single']") |> render_click()

    [appearance] = Tracking.list_plate_appearances(game.id)
    assert appearance.player_id == batter.id
    assert appearance.result == "single"
    assert appearance.end_bases["first"] == batter.id
    assert render(view) =~ next_batter.name

    view |> element("#undo-last-button") |> render_click()

    assert Tracking.list_plate_appearances(game.id) == []
    assert render(view) =~ next_batter.name
  end

  test "records extra-base hits with expected bases and scoring", %{conn: conn} do
    game = game_fixture()
    [first_batter, second_batter, third_batter] = lineup_fixture(game)
    {:ok, view, _html} = live(conn, ~p"/games/#{game.id}/scoring")

    view |> element("button[phx-value-result='double']") |> render_click()
    [double] = Tracking.list_plate_appearances(game.id)
    assert double.player_id == first_batter.id
    assert double.end_bases["second"] == first_batter.id

    view |> element("button[phx-value-result='triple']") |> render_click()
    view |> element("button[phx-click='confirm_result_modal']") |> render_click()

    [triple, _double] = Tracking.list_plate_appearances(game.id)
    assert triple.player_id == second_batter.id
    assert triple.runs_scored == 1
    assert triple.rbis == 1
    assert triple.end_bases["third"] == second_batter.id

    view |> element("button[phx-value-result='home_run']") |> render_click()
    [home_run, _triple, _double] = Tracking.list_plate_appearances(game.id)
    assert home_run.player_id == third_batter.id
    assert home_run.runs_scored == 2
    assert home_run.rbis == 2
    assert home_run.end_bases == %{"first" => nil, "second" => nil, "third" => nil}
    assert Tracking.get_game!(game.id).our_score == 3
  end

  test "walks and strikeouts normalize counts", %{conn: conn} do
    game = game_fixture()
    lineup_fixture(game)
    {:ok, view, _html} = live(conn, ~p"/games/#{game.id}/scoring")

    view |> element("#pitch-ball-button") |> render_click()
    view |> element("#pitch-ball-button") |> render_click()
    view |> element("#pitch-ball-button") |> render_click()
    view |> element("#pitch-ball-button") |> render_click()

    [walk] = Tracking.list_plate_appearances(game.id)
    assert walk.result == "walk"
    assert walk.balls == 4

    view |> element("#pitch-strike-button") |> render_click()
    view |> element("#pitch-strike-button") |> render_click()
    view |> element("#pitch-strike-button") |> render_click()

    [strikeout, _walk] = Tracking.list_plate_appearances(game.id)
    assert strikeout.result == "strikeout"
    assert strikeout.strikes == 3
  end

  test "blocks home runs that exceed the differential cap", %{conn: conn} do
    game = game_fixture()
    lineup_fixture(game)
    {:ok, view, _html} = live(conn, ~p"/games/#{game.id}/scoring")

    view |> element("button[phx-value-result='home_run']") |> render_click()
    view |> element("button[phx-value-result='home_run']") |> render_click()
    view |> element("button[phx-value-result='home_run']") |> render_click()

    assert Tracking.list_plate_appearances(game.id) |> length() == 2
    assert Tracking.get_game!(game.id).away_home_runs == 2
    assert render(view) =~ "Home run cap reached"
  end

  test "opponent home runs obey the differential cap", %{conn: conn} do
    game = game_fixture(%{home_home_runs: 2})
    lineup_fixture(game)
    {:ok, view, _html} = live(conn, ~p"/games/#{game.id}/scoring")

    Enum.each(1..3, fn _ ->
      view |> element("button[phx-value-result='out']") |> render_click()
    end)

    view |> element("button[phx-click='inc_opp_home_run']") |> render_click()

    game = Tracking.get_game!(game.id)
    assert game.home_home_runs == 2
    assert game.away_home_runs == 0
    assert game.opp_score == 0
    assert render(view) =~ "Home run cap reached"
  end

  test "opponent runs and outs can be undone", %{conn: conn} do
    game = game_fixture()
    lineup_fixture(game)
    {:ok, view, _html} = live(conn, ~p"/games/#{game.id}/scoring")

    Enum.each(1..3, fn _ ->
      view |> element("button[phx-value-result='out']") |> render_click()
    end)

    view |> element("button[phx-click='inc_opp_runs']") |> render_click()
    view |> element("button[phx-click='inc_opp_outs']") |> render_click()

    inning = Tracking.list_innings(game.id) |> List.first()
    assert inning.opp_runs == 1
    assert inning.opp_outs == 1
    assert Tracking.get_game!(game.id).opp_score == 1

    view |> element("#undo-last-button") |> render_click()

    inning = Tracking.list_innings(game.id) |> List.first()
    assert inning.opp_runs == 1
    assert inning.opp_outs == 0
    assert Tracking.get_game!(game.id).opp_score == 1
  end

  test "runner modal can customize destinations and rejects conflicts", %{conn: conn} do
    game = game_fixture()
    [runner, batter | _] = lineup_fixture(game)
    {:ok, view, _html} = live(conn, ~p"/games/#{game.id}/scoring")

    view |> element("button[phx-value-result='single']") |> render_click()
    view |> element("button[phx-value-result='single']") |> render_click()

    assert has_element?(view, "button[phx-click='confirm_result_modal']")

    view
    |> element("button[phx-value-runner='first'][phx-value-destination='home']")
    |> render_click()

    view |> element("button[phx-click='confirm_result_modal']") |> render_click()

    [single_with_runner, leadoff_single] = Tracking.list_plate_appearances(game.id)
    assert leadoff_single.player_id == runner.id
    assert single_with_runner.player_id == batter.id
    assert single_with_runner.runs_scored == 1
    assert single_with_runner.end_bases["first"] == batter.id
  end

  test "runner modal conflicts do not persist a plate appearance", %{conn: conn} do
    game = game_fixture()
    lineup_fixture(game)
    {:ok, view, _html} = live(conn, ~p"/games/#{game.id}/scoring")

    view |> element("button[phx-value-result='single']") |> render_click()
    view |> element("button[phx-value-result='single']") |> render_click()

    view
    |> element("button[phx-value-runner='first'][phx-value-destination='first']")
    |> render_click()

    view |> element("button[phx-click='confirm_result_modal']") |> render_click()

    assert Tracking.list_plate_appearances(game.id) |> length() == 1
    assert render(view) =~ "Runner destinations conflict"
  end

  test "inserted and skipped batters are persisted", %{conn: conn} do
    game = game_fixture()
    lineup_fixture(game)
    bench_player = player_fixture()
    {:ok, view, _html} = live(conn, ~p"/games/#{game.id}/scoring")

    view |> element("#insert-batter-button") |> render_click()

    view
    |> element("button[phx-value-player_id='#{bench_player.id}']")
    |> render_click()

    view |> element("button[phx-value-result='single']") |> render_click()

    [inserted] = Tracking.list_plate_appearances(game.id)
    assert inserted.player_id == bench_player.id
    assert inserted.inserted_batter

    view |> element("#skip-batter-button") |> render_click()

    [skipped, _inserted] = Tracking.list_plate_appearances(game.id)
    assert skipped.skip
    assert skipped.result == "out"
  end

  test "manual base controls clear and reset transient base state", %{conn: conn} do
    game = game_fixture()
    [batter | _] = lineup_fixture(game)
    {:ok, view, _html} = live(conn, ~p"/games/#{game.id}/scoring")

    view |> element("button[phx-value-result='single']") |> render_click()
    assert render(view) =~ batter.name

    view |> element("button[phx-click='clear_base'][phx-value-base='first']") |> render_click()
    assert render(view) =~ "Empty"

    view |> element("button[phx-click='reset_bases']") |> render_click()
    assert render(view) =~ "Empty"
  end

  test "reset game clears tracked scoring state", %{conn: conn} do
    game = game_fixture()
    lineup_fixture(game)
    {:ok, view, _html} = live(conn, ~p"/games/#{game.id}/scoring")

    view |> element("button[phx-value-result='home_run']") |> render_click()
    view |> element("#reset-game-state-button") |> render_click()

    game = Tracking.get_game!(game.id)
    assert game.our_score == 0
    assert game.away_home_runs == 0
    assert Tracking.list_plate_appearances(game.id) == []
  end
end
