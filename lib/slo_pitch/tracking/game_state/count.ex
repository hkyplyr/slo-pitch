defmodule SloPitch.Tracking.GameState.Count do
  @moduledoc """
  TODO - add moduledoc
  """
  @max_strikes 3
  @max_balls 4

  @type t :: %__MODULE__{
          balls: non_neg_integer(),
          strikes: non_neg_integer()
        }

  defstruct balls: 0, strikes: 0

  @spec increment_strikes(t()) :: t() | :strikeout
  def increment_strikes(%__MODULE__{} = count) do
    case count.strikes + 1 do
      @max_strikes -> :strikeout
      strikes -> %{count | strikes: strikes}
    end
  end

  @spec increment_balls(t()) :: t() | :walk
  def increment_balls(%__MODULE__{} = count) do
    case count.balls + 1 do
      @max_balls -> :walk
      balls -> %{count | balls: balls}
    end
  end
end
