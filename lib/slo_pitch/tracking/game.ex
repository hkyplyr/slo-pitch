defmodule SloPitch.Tracking.Game do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(scheduled in_progress final)
  @home_sides ~w(home away)

  schema "games" do
    field :opponent_name, :string
    field :played_on, :date
    field :location, :string
    field :status, :string, default: "scheduled"
    field :home_or_away, :string, default: "away"
    field :our_score, :integer, default: 0
    field :opp_score, :integer, default: 0
    field :home_home_runs, :integer, default: 0
    field :away_home_runs, :integer, default: 0

    has_many :lineup_slots, SloPitch.Tracking.GameLineupSlot
    has_many :innings, SloPitch.Tracking.GameInning
    has_many :plate_appearances, SloPitch.Tracking.PlateAppearance

    timestamps(type: :utc_datetime)
  end

  def changeset(game, attrs) do
    game
    |> cast(attrs, [
      :opponent_name,
      :played_on,
      :location,
      :status,
      :home_or_away,
      :our_score,
      :opp_score,
      :home_home_runs,
      :away_home_runs
    ])
    |> validate_required([:opponent_name, :played_on, :status, :home_or_away])
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:home_or_away, @home_sides)
    |> validate_number(:our_score, greater_than_or_equal_to: 0)
    |> validate_number(:opp_score, greater_than_or_equal_to: 0)
    |> validate_number(:home_home_runs, greater_than_or_equal_to: 0)
    |> validate_number(:away_home_runs, greater_than_or_equal_to: 0)
  end
end
