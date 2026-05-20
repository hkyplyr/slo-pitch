defmodule SloPitch.Tracking.GameState.PlayerStatistics do
  @moduledoc """
  TODO - add moduledoc
  """

  @type t :: %__MODULE__{
          single: non_neg_integer(),
          double: non_neg_integer(),
          triple: non_neg_integer(),
          home_run: non_neg_integer(),
          strikeout: non_neg_integer(),
          walk: non_neg_integer(),
          run: non_neg_integer(),
          rbi: non_neg_integer(),
          out: non_neg_integer()
        }

  @type normalized_stats :: %{
          plate_appearances: non_neg_integer(),
          at_bats: non_neg_integer(),
          runs: non_neg_integer(),
          hits: non_neg_integer(),
          doubles: non_neg_integer(),
          triples: non_neg_integer(),
          home_runs: non_neg_integer(),
          rbis: non_neg_integer(),
          walks: non_neg_integer(),
          strikeouts: non_neg_integer(),
          average: float(),
          slugging: float()
        }

  defstruct single: 0,
            double: 0,
            triple: 0,
            home_run: 0,
            strikeout: 0,
            walk: 0,
            run: 0,
            rbi: 0,
            out: 0

  @spec record(t(), atom(), non_neg_integer()) :: t()
  def record(stats, statistic, value), do: Map.update!(stats, statistic, &(&1 + value))

  @spec normalize(t()) :: normalized_stats()
  def normalize(stats) do
    hits = stats.single + stats.double + stats.triple + stats.home_run
    at_bats = hits + stats.out
    slugging = stats.single + 2 * stats.double + 3 * stats.triple + 4 * stats.home_run

    %{
      plate_appearances: at_bats + stats.walk,
      at_bats: at_bats,
      runs: stats.run,
      hits: hits,
      doubles: stats.double,
      triples: stats.triple,
      home_runs: stats.home_run,
      rbis: stats.rbi,
      walks: stats.walk,
      strikeouts: stats.strikeout,
      average: if(at_bats > 0, do: hits / at_bats, else: 0.0),
      slugging: if(at_bats > 0, do: slugging / at_bats, else: 0.0)
    }
  end
end
