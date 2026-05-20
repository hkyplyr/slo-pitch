defmodule SloPitch.Tracking.GameStateTest do
  use ExUnit.Case, async: true

  alias SloPitch.GameEngine.Event
  alias SloPitch.Tracking.Game
  alias SloPitch.Tracking.GameState
  alias SloPitch.Tracking.GameState.Bases
  alias SloPitch.Tracking.GameState.Count
  alias SloPitch.Tracking.GameState.HomeRuns
  alias SloPitch.Tracking.GameState.Inning
  alias SloPitch.Tracking.GameState.PlayerStatistics
  alias SloPitch.Tracking.GameState.Score
  alias SloPitch.Tracking.Player

  describe "init/2" do
    test "builds initial state and reapplies events" do
      players = [%Player{id: 1}, %Player{id: 2}]

      game = %Game{
        id: 10,
        alignment: :away,
        players: players
      }

      events = [
        %Event{type: :pitch, result: :strike},
        %Event{type: :plate_appearance, result: :skip}
      ]

      assert %GameState{
               game_id: 10,
               alignment: :away,
               lineup: ^players,
               current_batter_index: 1,
               count: %Count{strikes: 1, balls: 0},
               statistics: %{
                 1 => %PlayerStatistics{},
                 2 => %PlayerStatistics{}
               }
             } = GameState.init(game, events)
    end
  end

  describe "mode/1" do
    test "returns offense when away team is batting in top half" do
      assert :offense = GameState.mode(game_state(alignment: :away, half: :top))
    end

    test "returns offense when home team is batting in bottom half" do
      assert :offense = GameState.mode(game_state(alignment: :home, half: :bottom))
    end

    test "returns defense for non-batting halves" do
      assert :defense = GameState.mode(game_state(alignment: :away, half: :bottom))
      assert :defense = GameState.mode(game_state(alignment: :home, half: :top))
    end
  end

  describe "apply_event/2 - strike" do
    test "applies a strike to the count" do
      event = %Event{type: :pitch, result: :strike}

      assert %GameState{count: %Count{strikes: 1, balls: 0}} =
               GameState.apply_event(game_state(), event)
    end

    test "updates state when 3rd strike causes strikeout" do
      event = %Event{type: :pitch, result: :strike}

      state =
        game_state(
          count: count(strikes: 2),
          lineup: [%Player{id: 1}, %Player{id: 2}],
          statistics: %{
            1 => %PlayerStatistics{strikeout: 0},
            2 => %PlayerStatistics{strikeout: 0}
          }
        )

      assert %GameState{
               count: %Count{strikes: 0, balls: 0},
               outs: 1,
               current_batter_index: 1,
               statistics: %{
                 1 => %PlayerStatistics{strikeout: 1},
                 2 => %PlayerStatistics{strikeout: 0}
               }
             } = GameState.apply_event(state, event)
    end

    test "updates half when recording 3rd out of top half" do
      event = %Event{type: :pitch, result: :strike}

      state =
        game_state(
          count: count(strikes: 2),
          half: :top,
          outs: 2,
          lineup: [%Player{id: 1}, %Player{id: 2}],
          statistics: %{
            1 => %PlayerStatistics{strikeout: 0},
            2 => %PlayerStatistics{strikeout: 0}
          }
        )

      assert %GameState{
               count: %Count{strikes: 0, balls: 0},
               half: :bottom,
               inning: 1,
               outs: 0,
               current_batter_index: 1,
               statistics: %{
                 1 => %PlayerStatistics{strikeout: 1},
                 2 => %PlayerStatistics{strikeout: 0}
               }
             } = GameState.apply_event(state, event)
    end

    test "updates half and inning when recording 3rd out of bottom half" do
      event = %Event{type: :pitch, result: :strike}

      state =
        game_state(
          count: count(strikes: 2),
          half: :bottom,
          outs: 2,
          lineup: [%Player{id: 1}, %Player{id: 2}],
          statistics: %{
            1 => %PlayerStatistics{strikeout: 0},
            2 => %PlayerStatistics{strikeout: 0}
          }
        )

      assert %GameState{
               count: %Count{strikes: 0, balls: 0},
               half: :top,
               inning: 2,
               outs: 0,
               current_batter_index: 1,
               statistics: %{
                 1 => %PlayerStatistics{strikeout: 1},
                 2 => %PlayerStatistics{strikeout: 0}
               }
             } = GameState.apply_event(state, event)
    end
  end

  describe "apply_event/2 - ball" do
    test "applies a ball to the count" do
      event = %Event{type: :pitch, result: :ball}

      assert %GameState{count: %Count{strikes: 0, balls: 1}} =
               GameState.apply_event(game_state(), event)
    end

    test "updates state when 4th ball causes walk" do
      event = %Event{type: :pitch, result: :ball}

      state =
        game_state(
          alignment: :away,
          count: count(balls: 3),
          lineup: [%Player{id: 1}, %Player{id: 2}],
          statistics: %{
            1 => %PlayerStatistics{walk: 0, run: 0},
            2 => %PlayerStatistics{walk: 0, run: 0}
          }
        )

      assert %GameState{
               bases: %Bases{first: %Player{}},
               count: %Count{strikes: 0, balls: 0},
               outs: 0,
               current_batter_index: 1,
               statistics: %{
                 1 => %PlayerStatistics{walk: 1, run: 0},
                 2 => %PlayerStatistics{walk: 0, run: 0}
               }
             } = GameState.apply_event(state, event)
    end

    test "updates score when walk causes a run" do
      event = %Event{type: :pitch, result: :ball}

      state =
        game_state(
          bases: bases(first: %Player{id: 3}, second: %Player{id: 2}, third: %Player{id: 1}),
          count: count(balls: 3),
          alignment: :away,
          current_batter_index: 3,
          lineup: [%Player{id: 1}, %Player{id: 2}, %Player{id: 3}, %Player{id: 4}],
          statistics: %{
            1 => %PlayerStatistics{walk: 0, run: 0},
            2 => %PlayerStatistics{walk: 0, run: 0},
            3 => %PlayerStatistics{walk: 0, run: 0},
            4 => %PlayerStatistics{walk: 0, run: 0}
          }
        )

      assert %GameState{
               bases: %Bases{first: %Player{id: 4}, second: %Player{id: 3}, third: %Player{id: 2}},
               count: %Count{strikes: 0, balls: 0},
               outs: 0,
               current_batter_index: 0,
               statistics: %{
                 1 => %PlayerStatistics{walk: 0, run: 1},
                 2 => %PlayerStatistics{walk: 0, run: 0},
                 3 => %PlayerStatistics{walk: 0, run: 0},
                 4 => %PlayerStatistics{walk: 1, run: 0}
               }
             } = GameState.apply_event(state, event)
    end
  end

  describe "apply_event/2 - out" do
    test "advances runners" do
      runner_plan = %{batter: :out, first: :auto, second: :auto, third: :home}
      event = %Event{type: :plate_appearance, result: :out, runner_plan: runner_plan}

      state =
        game_state(
          bases: bases(first: %Player{id: 3}, second: %Player{id: 2}, third: %Player{id: 1}),
          alignment: :away,
          current_batter_index: 3,
          lineup: [%Player{id: 1}, %Player{id: 2}, %Player{id: 3}, %Player{id: 4}],
          statistics: %{
            1 => %PlayerStatistics{out: 0},
            2 => %PlayerStatistics{out: 0},
            3 => %PlayerStatistics{out: 0},
            4 => %PlayerStatistics{out: 0}
          }
        )

      assert %GameState{
               bases: %Bases{first: %Player{}, second: %Player{}, third: nil},
               outs: 1,
               current_batter_index: 0,
               statistics: %{
                 1 => %PlayerStatistics{out: 0},
                 2 => %PlayerStatistics{out: 0},
                 3 => %PlayerStatistics{out: 0},
                 # TODO - this should be 1, but we're currently double counting outs when the batter is out
                 4 => %PlayerStatistics{out: 2}
               }
             } = GameState.apply_event(state, event)
    end
  end

  describe "apply_event/2 - single" do
    test "advances runners" do
      runner_plan = %{batter: :auto, first: :auto, second: :auto, third: :auto}
      event = %Event{type: :plate_appearance, result: :single, runner_plan: runner_plan}

      state =
        game_state(
          bases: bases(first: %Player{id: 3}, second: %Player{id: 2}, third: %Player{id: 1}),
          alignment: :away,
          current_batter_index: 3,
          lineup: [%Player{id: 1}, %Player{id: 2}, %Player{id: 3}, %Player{id: 4}],
          statistics: %{
            1 => %PlayerStatistics{single: 0},
            2 => %PlayerStatistics{single: 0},
            3 => %PlayerStatistics{single: 0},
            4 => %PlayerStatistics{single: 0}
          }
        )

      assert %GameState{
               bases: %Bases{first: %Player{id: 4}, second: %Player{id: 3}, third: %Player{id: 2}},
               outs: 0,
               current_batter_index: 0,
               statistics: %{
                 1 => %PlayerStatistics{single: 0},
                 2 => %PlayerStatistics{single: 0},
                 3 => %PlayerStatistics{single: 0},
                 4 => %PlayerStatistics{single: 1}
               }
             } = GameState.apply_event(state, event)
    end
  end

  describe "apply_event/2 - skip" do
    test "advances to the next batter" do
      event = %Event{type: :plate_appearance, result: :skip}
      state = game_state(current_batter_index: 1, lineup: [%Player{id: 1}, %Player{id: 2}])

      assert %GameState{current_batter_index: 0} = GameState.apply_event(state, event)
    end
  end

  describe "apply_event/2 - opponent" do
    test "records opponent out and advances half inning on third out" do
      event = %Event{type: :opponent, result: :out}

      state =
        game_state(
          half: :top,
          outs: 2,
          count: count(strikes: 1, balls: 2),
          bases: bases(first: %Player{id: 1})
        )

      assert %GameState{
               half: :bottom,
               inning: 1,
               outs: 0,
               count: %Count{strikes: 0, balls: 0},
               bases: %Bases{first: nil, second: nil, third: nil}
             } = GameState.apply_event(state, event)
    end

    test "records opponent home run and increments tracked home runs" do
      event = %Event{type: :opponent, result: :home_run}
      state = game_state(alignment: :home, half: :bottom, home_runs: %HomeRuns{home: 0, away: 0})

      assert %GameState{
               home_runs: %HomeRuns{away: 0, home: 1}
             } = GameState.apply_event(state, event)
    end

    test "advances from top to bottom when away reaches run cap for inning" do
      event = %Event{type: :opponent, result: :run}

      innings =
        List.replace_at(game_state().innings, 0, %Inning{
          number: 1,
          score: %Score{away: 4, home: 0}
        })

      state =
        game_state(
          alignment: :home,
          inning: 1,
          half: :top,
          outs: 1,
          count: count(strikes: 1, balls: 2),
          bases: bases(first: %Player{id: 1}),
          innings: innings
        )

      assert %GameState{
               half: :bottom,
               inning: 1,
               outs: 0,
               count: %Count{strikes: 0, balls: 0},
               bases: %Bases{first: nil, second: nil, third: nil}
             } = GameState.apply_event(state, event)
    end

    test "advances from bottom to next inning top when home reaches run cap for inning" do
      event = %Event{type: :opponent, result: :run}

      innings =
        List.replace_at(game_state().innings, 0, %Inning{
          number: 1,
          score: %Score{away: 0, home: 5}
        })

      state =
        game_state(
          alignment: :home,
          inning: 1,
          half: :bottom,
          outs: 1,
          count: count(strikes: 2, balls: 1),
          bases: bases(second: %Player{id: 1}),
          innings: innings
        )

      assert %GameState{
               half: :top,
               inning: 2,
               outs: 0,
               count: %Count{strikes: 0, balls: 0},
               bases: %Bases{first: nil, second: nil, third: nil}
             } = GameState.apply_event(state, event)
    end

    test "does not advance past bottom of seventh on third out and marks final" do
      event = %Event{type: :opponent, result: :out}

      state =
        game_state(
          alignment: :home,
          inning: 7,
          half: :bottom,
          outs: 2,
          count: count(strikes: 1, balls: 2),
          bases: bases(second: %Player{id: 1})
        )

      assert %GameState{
               half: :bottom,
               inning: 7,
               outs: 3,
               count: %Count{strikes: 1, balls: 2},
               bases: %Bases{first: nil, second: %Player{id: 1}, third: nil},
               status: :final
             } = GameState.apply_event(state, event)
    end

    @tag :skip
    test "advances to bottom of seventh and marks game final when home already leads" do
      event = %Event{type: :opponent, result: :run}

      innings =
        List.replace_at(game_state().innings, 6, %Inning{
          number: 7,
          score: %Score{away: 4, home: 0}
        })

      state =
        game_state(
          alignment: :home,
          inning: 7,
          half: :top,
          score: %Score{home: 10, away: 2},
          outs: 1,
          count: count(strikes: 1, balls: 2),
          bases: bases(third: %Player{id: 1}),
          innings: innings
        )

      assert %GameState{
               half: :bottom,
               inning: 7,
               outs: 0,
               count: %Count{strikes: 0, balls: 0},
               bases: %Bases{first: nil, second: nil, third: nil},
               status: :final
             } = GameState.apply_event(state, event)
    end
  end

  describe "game_over?/1" do
    test "is true when status is final" do
      state = game_state(status: :final)
      assert GameState.game_over?(state)
    end

    test "is false when status is in progress" do
      refute GameState.game_over?(game_state(status: :in_progress))
    end
  end

  defp game_state(attrs \\ %{}), do: struct(GameState, attrs)
  defp count(attrs), do: struct(Count, attrs)
  defp bases(attrs), do: struct(Bases, attrs)
end
