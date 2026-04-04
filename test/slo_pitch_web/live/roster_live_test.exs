defmodule SloPitchWeb.RosterLiveTest do
  use SloPitchWeb.ConnCase, async: true

  alias SloPitch.Tracking

  test "adds a player and toggles active state", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/roster")

    assert has_element?(view, "#player-form")

    view
    |> form("#player-form", player: %{name: "Alex Rivera", jersey_number: "12"})
    |> render_submit()

    [player] = Tracking.list_players()
    assert player.name == "Alex Rivera"
    assert has_element?(view, "#roster-player-#{player.id}")

    view
    |> element("#roster-player-#{player.id} button")
    |> render_click()

    refute Tracking.list_players() |> List.first() |> Map.fetch!(:active)
  end

  test "rejects blank and duplicate player names", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/roster")

    view
    |> form("#player-form", player: %{name: " ", jersey_number: "12"})
    |> render_submit()

    assert Tracking.list_players() == []

    name = "Duplicate #{System.unique_integer([:positive])}"
    player_fixture(%{name: name})

    view
    |> form("#player-form", player: %{name: name, jersey_number: "14"})
    |> render_submit()

    assert Tracking.list_players() |> Enum.count(&(&1.name == name)) == 1
  end
end
