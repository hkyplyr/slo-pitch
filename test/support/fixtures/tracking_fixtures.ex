defmodule SloPitch.TrackingFixtures do
  @moduledoc """
  Test fixtures for the tracking context.
  """

  alias SloPitch.Tracking

  def player_fixture(attrs \\ %{}) do
    unique = System.unique_integer([:positive])

    attrs =
      Map.merge(
        %{
          name: "Player #{unique}",
          jersey_number: rem(unique, 99),
          active: true
        },
        attrs
      )

    {:ok, player} = Tracking.create_player(attrs)
    player
  end

  def game_fixture(attrs \\ %{}) do
    attrs =
      Map.merge(
        %{
          opponent_name: "Prairie Heat",
          played_on: ~D[2026-04-02],
          location: "Rotary Park",
          status: "scheduled",
          alignment: :away
        },
        attrs
      )

    {:ok, game} = Tracking.create_game(attrs)
    game
  end

  def lineup_fixture(game, players_or_attrs \\ nil) do
    players =
      case players_or_attrs do
        nil ->
          unique = System.unique_integer([:positive])

          Enum.map(1..3, fn index ->
            player_fixture(%{name: "Lineup Player #{unique}-#{index}"})
          end)

        players when is_list(players) ->
          players
      end

    {:ok, _slots} = Tracking.set_game_lineup(game.id, Enum.map(players, & &1.id))
    players
  end
end
