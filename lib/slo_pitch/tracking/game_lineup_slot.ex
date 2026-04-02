defmodule SloPitch.Tracking.GameLineupSlot do
  use Ecto.Schema
  import Ecto.Changeset

  schema "game_lineup_slots" do
    field :batting_order, :integer
    field :starter, :boolean, default: true

    belongs_to :game, SloPitch.Tracking.Game
    belongs_to :player, SloPitch.Tracking.Player

    timestamps(type: :utc_datetime)
  end

  def changeset(slot, attrs) do
    slot
    |> cast(attrs, [:batting_order, :starter, :game_id, :player_id])
    |> validate_required([:batting_order, :game_id, :player_id])
    |> validate_number(:batting_order, greater_than: 0)
    |> assoc_constraint(:game)
    |> assoc_constraint(:player)
    |> unique_constraint([:game_id, :batting_order])
    |> unique_constraint([:game_id, :player_id])
  end
end
