defmodule SloPitch.Tracking.GameInning do
  use Ecto.Schema
  import Ecto.Changeset

  schema "game_innings" do
    field :inning_number, :integer
    field :our_runs, :integer, default: 0
    field :opp_runs, :integer, default: 0
    field :opp_outs, :integer, default: 0

    belongs_to :game, SloPitch.Tracking.Game

    timestamps(type: :utc_datetime)
  end

  def changeset(inning, attrs) do
    inning
    |> cast(attrs, [:inning_number, :our_runs, :opp_runs, :opp_outs, :game_id])
    |> validate_required([:inning_number, :game_id])
    |> validate_number(:inning_number, greater_than: 0)
    |> validate_number(:our_runs, greater_than_or_equal_to: 0)
    |> validate_number(:opp_runs, greater_than_or_equal_to: 0)
    |> validate_number(:opp_outs, greater_than_or_equal_to: 0, less_than_or_equal_to: 3)
    |> assoc_constraint(:game)
    |> unique_constraint([:game_id, :inning_number])
  end
end
