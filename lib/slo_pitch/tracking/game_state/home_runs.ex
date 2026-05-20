defmodule SloPitch.Tracking.GameState.HomeRuns do
  @moduledoc """
  TODO - add moduledoc
  """

  @type t :: %__MODULE__{
          home: non_neg_integer(),
          away: non_neg_integer()
        }

  defstruct home: 0, away: 0

  def increment_away(%__MODULE__{} = home_runs), do: %{home_runs | away: home_runs.away + 1}
  def increment_home(%__MODULE__{} = home_runs), do: %{home_runs | home: home_runs.home + 1}
end
