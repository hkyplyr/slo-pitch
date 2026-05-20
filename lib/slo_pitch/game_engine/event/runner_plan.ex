defmodule SloPitch.GameEngine.Event.RunnerPlan do
  @moduledoc """
  TODO - add moduledoc
  """
  use Ecto.Schema

  import Ecto.Changeset

  @type t :: map()

  @targets ~w(auto first second third home out)a

  @primary_key false
  embedded_schema do
    field :batter, Ecto.Enum, values: @targets
    field :first, Ecto.Enum, values: @targets
    field :second, Ecto.Enum, values: @targets
    field :third, Ecto.Enum, values: @targets
  end

  def changeset(struct \\ %__MODULE__{}, attrs) do
    cast(struct, attrs, __schema__(:fields))
  end
end
