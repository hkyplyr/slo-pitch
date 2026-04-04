defmodule SloPitch.Tracking.PlateAppearance do
  use Ecto.Schema
  import Ecto.Changeset

  @results ~w(single double triple home_run walk strikeout out)

  schema "plate_appearances" do
    field :sequence_number, :integer
    field :inning, :integer
    field :result, :string
    field :balls, :integer, default: 0
    field :strikes, :integer, default: 0
    field :runs_scored, :integer, default: 0
    field :rbis, :integer, default: 0
    field :skip, :boolean, default: false
    field :inserted_batter, :boolean, default: false
    field :end_bases, :map

    belongs_to :game, SloPitch.Tracking.Game
    belongs_to :player, SloPitch.Tracking.Player
    belongs_to :lineup_slot, SloPitch.Tracking.GameLineupSlot

    timestamps(type: :utc_datetime)
  end

  def changeset(plate_appearance, attrs) do
    plate_appearance
    |> cast(attrs, [
      :sequence_number,
      :inning,
      :result,
      :balls,
      :strikes,
      :runs_scored,
      :rbis,
      :skip,
      :inserted_batter,
      :end_bases,
      :game_id,
      :player_id,
      :lineup_slot_id
    ])
    |> validate_required([:sequence_number, :inning, :result, :game_id, :player_id])
    |> validate_number(:sequence_number, greater_than: 0)
    |> validate_number(:inning, greater_than: 0)
    |> validate_inclusion(:result, @results)
    |> validate_number(:balls, greater_than_or_equal_to: 0, less_than_or_equal_to: 4)
    |> validate_number(:strikes, greater_than_or_equal_to: 0, less_than_or_equal_to: 3)
    |> validate_number(:runs_scored, greater_than_or_equal_to: 0)
    |> validate_number(:rbis, greater_than_or_equal_to: 0)
    |> validate_result_count_consistency()
    |> assoc_constraint(:game)
    |> assoc_constraint(:player)
    |> assoc_constraint(:lineup_slot)
    |> unique_constraint([:game_id, :sequence_number])
  end

  defp validate_result_count_consistency(changeset) do
    result = get_field(changeset, :result)
    balls = get_field(changeset, :balls)
    strikes = get_field(changeset, :strikes)

    changeset
    |> maybe_validate_walk_count(result, balls)
    |> maybe_validate_strikeout_count(result, strikes)
  end

  defp maybe_validate_walk_count(changeset, "walk", balls) when balls < 4 do
    add_error(changeset, :balls, "must be 4 for a walk")
  end

  defp maybe_validate_walk_count(changeset, _result, _balls), do: changeset

  defp maybe_validate_strikeout_count(changeset, "strikeout", strikes) when strikes < 3 do
    add_error(changeset, :strikes, "must be 3 for a strikeout")
  end

  defp maybe_validate_strikeout_count(changeset, _result, _strikes), do: changeset
end
