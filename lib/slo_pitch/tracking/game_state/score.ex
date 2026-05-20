defmodule SloPitch.Tracking.GameState.Score do
  @moduledoc """
  TODO - add moduledoc
  """
  @max_runs 5

  @type t :: %__MODULE__{
          home: non_neg_integer(),
          away: non_neg_integer()
        }

  @type alignment :: :away | :home

  defstruct home: 0, away: 0

  @spec increment(t(), alignment(), non_neg_integer()) :: t()
  def increment(%__MODULE__{} = score, :away, runs), do: %{score | away: score.away + runs}
  def increment(%__MODULE__{} = score, :home, runs), do: %{score | home: score.home + runs}

  @spec increment_capped(t(), alignment(), non_neg_integer()) :: t()
  def increment_capped(%__MODULE__{} = score, :away, runs),
    do: %{score | away: min(score.away + runs, @max_runs)}

  def increment_capped(%__MODULE__{} = score, :home, runs),
    do: %{score | home: min(score.home + runs, @max_runs)}
end
