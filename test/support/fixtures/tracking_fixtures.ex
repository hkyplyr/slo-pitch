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
          home_or_away: "away"
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

  def plate_appearance_fixture(attrs \\ %{}) do
    game = Map.get(attrs, :game) || game_fixture()
    player = Map.get(attrs, :player) || player_fixture()

    attrs =
      attrs
      |> Map.drop([:game, :player])
      |> Map.merge(%{
        game_id: game.id,
        player_id: player.id,
        inning: Map.get(attrs, :inning, 1),
        result: Map.get(attrs, :result, "single"),
        balls: Map.get(attrs, :balls, 0),
        strikes: Map.get(attrs, :strikes, 0),
        runs_scored: Map.get(attrs, :runs_scored, 0),
        rbis: Map.get(attrs, :rbis, 0),
        skip: Map.get(attrs, :skip, false),
        inserted_batter: Map.get(attrs, :inserted_batter, false),
        end_bases: Map.get(attrs, :end_bases)
      })

    {:ok, plate_appearance} = Tracking.record_plate_appearance(attrs)
    plate_appearance
  end
end
