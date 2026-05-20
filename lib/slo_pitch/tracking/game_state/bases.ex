defmodule SloPitch.Tracking.GameState.Bases do
  @moduledoc """
  TODO - add moduledoc
  """

  @type runner_id :: integer() | nil

  @type t :: %__MODULE__{
          first: runner_id(),
          second: runner_id(),
          third: runner_id()
        }

  defstruct [:first, :second, :third]

  def occupied?(%__MODULE__{first: nil, second: nil, third: nil}), do: false
  def occupied?(%__MODULE__{}), do: true
end
