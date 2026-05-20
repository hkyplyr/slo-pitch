defmodule SloPitch.Tracking.Game do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(scheduled in_progress final)
  @home_sides ~w(home away)a

  @type t :: %__MODULE__{}

  schema "games" do
    field :opponent_name, :string
    field :played_on, :date
    field :location, :string
    field :status, :string, default: "scheduled"
    field :alignment, Ecto.Enum, values: @home_sides

    has_many :lineup_slots, SloPitch.Tracking.GameLineupSlot, preload_order: [asc: :batting_order]
    has_many :players, through: [:lineup_slots, :player]

    timestamps(type: :utc_datetime)
  end

  def changeset(game, attrs) do
    game
    |> cast(attrs, [
      :opponent_name,
      :played_on,
      :location,
      :status,
      :alignment
    ])
    |> validate_required([:opponent_name, :played_on, :status, :alignment])
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:alignment, @home_sides)
  end
end
