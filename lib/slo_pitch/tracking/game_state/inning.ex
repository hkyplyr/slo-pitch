defmodule SloPitch.Tracking.GameState.Inning do
  @moduledoc """
  TODO - add moduledoc
  """

  alias SloPitch.Tracking.GameState.Score

  @type t :: %__MODULE__{
          number: non_neg_integer(),
          score: Score.t()
        }

  @type alignment :: :away | :home
  @final_inning 7

  defstruct [:number, score: %Score{}]

  @spec increment_score(list(t()), non_neg_integer(), alignment(), non_neg_integer()) :: list(t())
  def increment_score(innings, number, alignment, runs),
    do: Enum.map(innings, &do_increment_score(&1, number, alignment, runs))

  defp do_increment_score(
         %__MODULE__{number: @final_inning} = inning,
         @final_inning,
         alignment,
         runs
       ),
       do: %{inning | score: Score.increment(inning.score, alignment, runs)}

  defp do_increment_score(%__MODULE__{number: number} = inning, number, alignment, runs),
    do: %{inning | score: Score.increment_capped(inning.score, alignment, runs)}

  defp do_increment_score(inning, _number, _alignment, _runs), do: inning
end
