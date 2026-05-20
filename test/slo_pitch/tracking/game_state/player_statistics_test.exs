defmodule SloPitch.Tracking.GameState.PlayerStatisticsTest do
  use SloPitch.DataCase, async: true

  alias SloPitch.Tracking.GameState.PlayerStatistics

  describe "record/3" do
    test "updates each field successfully" do
      %PlayerStatistics{
        single: 1,
        double: 1,
        triple: 1,
        home_run: 1,
        strikeout: 1,
        walk: 1,
        run: 1,
        rbi: 1,
        out: 1
      } =
        %PlayerStatistics{}
        |> Map.from_struct()
        |> Map.keys()
        |> Enum.reduce(%PlayerStatistics{}, &PlayerStatistics.record(&2, &1, 1))
    end
  end

  describe "normalize/1" do
    player_stats = %PlayerStatistics{
      single: 1,
      double: 1,
      triple: 1,
      home_run: 1,
      strikeout: 1,
      walk: 1,
      run: 1,
      rbi: 1,
      out: 1
    }

    assert %{
             plate_appearances: 6,
             at_bats: 5,
             runs: 1,
             hits: 4,
             doubles: 1,
             triples: 1,
             home_runs: 1,
             rbis: 1,
             walks: 1,
             strikeouts: 1,
             average: 0.8,
             slugging: 2.0
           } = PlayerStatistics.normalize(player_stats)
  end
end
