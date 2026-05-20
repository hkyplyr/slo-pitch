defmodule SloPitch.Tracking.Player do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "players" do
    field :name, :string
    field :jersey_number, :integer
    field :active, :boolean, default: true

    has_many :lineup_slots, SloPitch.Tracking.GameLineupSlot

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

  def display_name(%__MODULE__{name: name, jersey_number: jersey_number}),
    do: "#{jersey_number} #{name}"

  def display_name(_player), do: "Empty"
end
