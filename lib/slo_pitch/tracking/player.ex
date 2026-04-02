defmodule SloPitch.Tracking.Player do
  use Ecto.Schema
  import Ecto.Changeset

  schema "players" do
    field :name, :string
    field :jersey_number, :integer
    field :active, :boolean, default: true

    has_many :lineup_slots, SloPitch.Tracking.GameLineupSlot
    has_many :plate_appearances, SloPitch.Tracking.PlateAppearance

    timestamps(type: :utc_datetime)
  end

  def changeset(player, attrs) do
    player
    |> cast(attrs, [:name, :jersey_number, :active])
    |> validate_required([:name])
    |> validate_length(:name, min: 2, max: 120)
    |> validate_number(:jersey_number, greater_than_or_equal_to: 0)
    |> unique_constraint(:name)
  end
end
