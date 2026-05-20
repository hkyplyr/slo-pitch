defmodule SloPitch.GameEngine.Event do
  @moduledoc """
  TODO - add moduledoc
  """
  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @type types :: :opponent | :pitch | :plate_appearance

  @type pitch_result :: :ball | :strike
  @type plate_appearance_result :: :double | :home_run | :out | :single | :skip | :triple
  @type opponent_result :: :home_run | :out | :run

  @event_types ~w(opponent pitch plate_appearance)a
  @event_results ~w(ball double home_run out run single skip strike triple)a

  schema "game_events" do
    field :type, Ecto.Enum, values: @event_types
    field :result, Ecto.Enum, values: @event_results

    embeds_one :runner_plan, SloPitch.GameEngine.Event.RunnerPlan

    belongs_to :game, SloPitch.Tracking.Game
    belongs_to :player, SloPitch.Tracking.Player

    timestamps()
  end

  def changeset(struct \\ %__MODULE__{}, attrs) do
    struct
    |> cast(attrs, __schema__(:fields) -- __schema__(:embeds))
    |> cast_embed(:runner_plan)
  end
end
