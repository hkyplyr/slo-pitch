defmodule SloPitchWeb.ScoringLive do
  use SloPitchWeb, :live_view

  alias SloPitch.Tracking

  @results [
    %{value: "single", label: "1B", color: "bg-emerald-500 hover:bg-emerald-600"},
    %{value: "double", label: "2B", color: "bg-green-500 hover:bg-green-600"},
    %{value: "triple", label: "3B", color: "bg-lime-500 hover:bg-lime-600"},
    %{value: "home_run", label: "HR", color: "bg-amber-500 hover:bg-amber-600"},
    %{value: "out", label: "OUT", color: "bg-zinc-600 hover:bg-zinc-700"}
  ]
  @max_innings 7

  @impl true
  def mount(params, _session, socket) do
    game_id = parse_game_id(params)
    game = Tracking.get_game!(game_id)
    lineup = Tracking.list_lineup_players(game.id)
    innings = Tracking.ensure_innings(game.id)
    phase = derive_phase(game, innings, Tracking.list_plate_appearances(game.id))

    {:ok,
     socket
     |> assign(:page_title, "Live Scoring")
     |> assign(:current_scope, nil)
     |> assign(:game, game)
     |> assign(:lineup, lineup)
     |> assign(:bench_players, Tracking.list_bench_players(game.id))
     |> assign(:batting_index, 0)
     |> assign(:selected_result, "single")
     |> assign(:results, @results)
     |> assign(:balls, 0)
     |> assign(:strikes, 0)
     |> assign(:bases, derive_bases(game.id))
     |> assign(:result_modal_open, false)
     |> assign(:pending_result, nil)
     |> assign(:modal_runner_plan, default_runner_plan())
     |> assign(:modal_error, nil)
     |> assign(:innings, innings)
     |> assign(:phase, phase)
     |> assign(:our_score, game.our_score)
     |> assign(:opp_score, game.opp_score)
     |> assign(:feed, build_feed(game.id))
     |> assign(:undo_history, [])
     |> assign(:insert_picker_open, false)
     |> assign(:inserted_player, nil)}
  end

  @impl true
  def handle_event(
        "select_result",
        %{"result" => result},
        %{assigns: %{phase: %{mode: :offense}}} = socket
      ) do
    socket = assign(socket, :selected_result, result)

    if result_requires_confirmation?(result, socket.assigns.bases) do
      {:noreply, open_result_modal(socket, result)}
    else
      {:noreply, record_result(socket, result, socket.assigns.balls, socket.assigns.strikes)}
    end
  end

  def handle_event("select_result", _params, socket), do: {:noreply, socket}

  def handle_event("record_ball", _params, %{assigns: %{phase: %{mode: :offense}}} = socket) do
    balls = min(socket.assigns.balls + 1, 4)

    if balls >= 4 do
      {:noreply, record_result(socket, "walk", 4, min(socket.assigns.strikes, 2))}
    else
      {:noreply, assign(socket, :balls, balls)}
    end
  end

  def handle_event("record_strike", _params, %{assigns: %{phase: %{mode: :offense}}} = socket) do
    strikes = min(socket.assigns.strikes + 1, 3)

    if strikes >= 3 do
      {:noreply, record_result(socket, "strikeout", min(socket.assigns.balls, 3), 3)}
    else
      {:noreply, assign(socket, :strikes, strikes)}
    end
  end

  def handle_event("record_ball", _params, socket), do: {:noreply, socket}
  def handle_event("record_strike", _params, socket), do: {:noreply, socket}

  def handle_event("reset_count", _params, socket) do
    {:noreply, socket |> assign(:balls, 0) |> assign(:strikes, 0)}
  end

  def handle_event("clear_base", %{"base" => base}, socket) do
    bases = Map.put(socket.assigns.bases, String.to_existing_atom(base), nil)
    {:noreply, assign(socket, :bases, bases)}
  end

  def handle_event("reset_bases", _params, socket) do
    {:noreply, assign(socket, :bases, empty_bases())}
  end

  def handle_event(
        "set_modal_runner_destination",
        %{"runner" => runner, "destination" => destination},
        socket
      ) do
    runner_key = String.to_existing_atom(runner)
    destination_key = String.to_existing_atom(destination)
    updated = Map.put(socket.assigns.modal_runner_plan, runner_key, destination_key)

    {:noreply, socket |> assign(:modal_runner_plan, updated) |> assign(:modal_error, nil)}
  end

  def handle_event("close_result_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:result_modal_open, false)
     |> assign(:pending_result, nil)
     |> assign(:modal_runner_plan, default_runner_plan())
     |> assign(:modal_error, nil)}
  end

  def handle_event("confirm_result_modal", _params, socket) do
    result = socket.assigns.pending_result || socket.assigns.selected_result

    {:noreply,
     record_result(
       socket,
       result,
       socket.assigns.balls,
       socket.assigns.strikes,
       socket.assigns.modal_runner_plan
     )}
  end

  def handle_event("inc_opp_runs", _params, %{assigns: %{phase: %{mode: :defense}}} = socket) do
    if socket.assigns.phase.mode != :defense do
      {:noreply, socket}
    else
      prev_game_counts = home_run_counts(socket.assigns.game)
      prev_runs = socket.assigns.phase.opp_runs
      prev_outs = socket.assigns.phase.opp_outs
      new_runs = min(socket.assigns.phase.opp_runs + 1, 5)

      {:ok, _inning} =
        Tracking.upsert_inning_runs(socket.assigns.game.id, socket.assigns.phase.inning, %{
          opp_runs: new_runs
        })

      {:ok, _game} = Tracking.refresh_game_score(socket.assigns.game.id)

      {:noreply,
       socket
       |> push_undo_event(%{
         type: :opp_state,
         inning: socket.assigns.phase.inning,
         opp_runs: prev_runs,
         opp_outs: prev_outs,
         home_home_runs: prev_game_counts.home,
         away_home_runs: prev_game_counts.away
       })
       |> reload_game_state()}
    end
  end

  def handle_event("inc_opp_home_run", _params, %{assigns: %{phase: %{mode: :defense}}} = socket) do
    if home_run_rule_violation?(socket.assigns.game, :opponent) do
      {:noreply,
       socket
       |> assign(:modal_error, "Home run cap reached: home/away HR difference cannot exceed 2.")
       |> put_flash(:error, "Home run cap reached: home/away HR difference cannot exceed 2.")}
    else
      prev_game_counts = home_run_counts(socket.assigns.game)
      prev_runs = socket.assigns.phase.opp_runs
      prev_outs = socket.assigns.phase.opp_outs
      new_runs = min(socket.assigns.phase.opp_runs + 1, 5)

      {:ok, _inning} =
        Tracking.upsert_inning_runs(socket.assigns.game.id, socket.assigns.phase.inning, %{
          opp_runs: new_runs
        })

      {:ok, _game} =
        Tracking.update_game(
          socket.assigns.game,
          opponent_hr_increment_attrs(socket.assigns.game)
        )

      {:ok, _game} = Tracking.refresh_game_score(socket.assigns.game.id)

      {:noreply,
       socket
       |> push_undo_event(%{
         type: :opp_state,
         inning: socket.assigns.phase.inning,
         opp_runs: prev_runs,
         opp_outs: prev_outs,
         home_home_runs: prev_game_counts.home,
         away_home_runs: prev_game_counts.away
       })
       |> reload_game_state()}
    end
  end

  def handle_event("inc_opp_outs", _params, %{assigns: %{phase: %{mode: :defense}}} = socket) do
    prev_game_counts = home_run_counts(socket.assigns.game)
    prev_runs = socket.assigns.phase.opp_runs
    prev_outs = socket.assigns.phase.opp_outs
    new_outs = min(socket.assigns.phase.opp_outs + 1, 3)

    {:ok, _inning} =
      Tracking.upsert_inning_runs(socket.assigns.game.id, socket.assigns.phase.inning, %{
        opp_outs: new_outs
      })

    {:noreply,
     socket
     |> push_undo_event(%{
       type: :opp_state,
       inning: socket.assigns.phase.inning,
       opp_runs: prev_runs,
       opp_outs: prev_outs,
       home_home_runs: prev_game_counts.home,
       away_home_runs: prev_game_counts.away
     })
     |> reload_game_state()}
  end

  def handle_event("inc_opp_runs", _params, socket), do: {:noreply, socket}
  def handle_event("inc_opp_home_run", _params, socket), do: {:noreply, socket}
  def handle_event("inc_opp_outs", _params, socket), do: {:noreply, socket}

  def handle_event(
        "open_insert_picker",
        _params,
        %{assigns: %{phase: %{mode: :offense}}} = socket
      ) do
    {:noreply, assign(socket, :insert_picker_open, true)}
  end

  def handle_event("open_insert_picker", _params, socket), do: {:noreply, socket}

  def handle_event("close_insert_picker", _params, socket) do
    {:noreply, assign(socket, :insert_picker_open, false)}
  end

  def handle_event("pick_insert_batter", %{"player_id" => player_id}, socket) do
    player = Enum.find(socket.assigns.bench_players, &(&1.id == String.to_integer(player_id)))

    {:noreply,
     socket
     |> assign(:inserted_player, player)
     |> assign(:insert_picker_open, false)}
  end

  def handle_event("skip_batter", _params, %{assigns: %{phase: %{mode: :offense}}} = socket) do
    batter = current_batter(socket.assigns)
    game_counts = home_run_counts(socket.assigns.game)

    {:ok, plate_appearance} =
      Tracking.record_plate_appearance(%{
        game_id: socket.assigns.game.id,
        player_id: batter.id,
        inning: socket.assigns.phase.inning,
        result: "out",
        balls: socket.assigns.balls,
        strikes: socket.assigns.strikes,
        runs_scored: 0,
        rbis: 0,
        skip: true,
        inserted_batter: false
      })

    {:noreply,
     socket
     |> push_undo_event(%{
       type: :pa,
       plate_appearance_id: plate_appearance.id,
       home_home_runs: game_counts.home,
       away_home_runs: game_counts.away
     })
     |> reload_game_state()
     |> next_batter()
     |> assign(:balls, 0)
     |> assign(:strikes, 0)
     |> assign(:inserted_player, nil)}
  end

  def handle_event("skip_batter", _params, socket), do: {:noreply, socket}

  def handle_event("undo_last", _params, socket) do
    case socket.assigns.undo_history do
      [event | rest] ->
        case event.type do
          :pa ->
            {:ok, _deleted} = Tracking.delete_plate_appearance(event.plate_appearance_id)

            {:ok, _game} =
              Tracking.update_game(socket.assigns.game, %{
                home_home_runs: event.home_home_runs,
                away_home_runs: event.away_home_runs
              })

            {:noreply, socket |> assign(:undo_history, rest) |> reload_game_state()}

          :opp_state ->
            {:ok, _inning} =
              Tracking.upsert_inning_runs(socket.assigns.game.id, event.inning, %{
                opp_runs: event.opp_runs,
                opp_outs: event.opp_outs
              })

            {:ok, _game} =
              Tracking.update_game(socket.assigns.game, %{
                home_home_runs: event.home_home_runs,
                away_home_runs: event.away_home_runs
              })

            {:ok, _game} = Tracking.refresh_game_score(socket.assigns.game.id)
            {:noreply, socket |> assign(:undo_history, rest) |> reload_game_state()}
        end

      [] ->
        {:ok, deleted} = Tracking.delete_latest_plate_appearance(socket.assigns.game.id)

        socket =
          if deleted && deleted.result == "home_run" do
            {:ok, _game} =
              Tracking.update_game(
                socket.assigns.game,
                our_hr_increment_attrs(socket.assigns.game, -1)
              )

            socket
          else
            socket
          end

        {:noreply, reload_game_state(socket)}
    end
  end

  def handle_event("reset_game_state", _params, socket) do
    {:ok, _game} = Tracking.reset_game_state(socket.assigns.game.id)

    {:noreply,
     socket
     |> assign(:batting_index, 0)
     |> assign(:balls, 0)
     |> assign(:strikes, 0)
     |> assign(:inserted_player, nil)
     |> assign(:undo_history, [])
     |> reload_game_state()}
  end

  defp next_batter(socket) do
    assign(
      socket,
      :batting_index,
      rem(socket.assigns.batting_index + 1, length(socket.assigns.lineup))
    )
  end

  defp current_batter(assigns), do: Enum.at(assigns.lineup, assigns.batting_index)

  defp inserted_or_current_batter(assigns), do: assigns.inserted_player || current_batter(assigns)

  defp empty_bases, do: %{first: nil, second: nil, third: nil}
  defp default_runner_plan, do: %{first: :auto, second: :auto, third: :auto, batter: :auto}

  defp derive_phase(game, innings, appearances) do
    inning_runs =
      appearances
      |> Enum.group_by(& &1.inning)
      |> Map.new(fn {inning, inning_appearances} ->
        outs =
          Enum.count(inning_appearances, fn pa ->
            pa.skip or pa.result in ["out", "strikeout"]
          end)

        runs = Enum.reduce(inning_appearances, 0, &(&1.runs_scored + &2))
        {inning, %{outs: outs, runs: runs}}
      end)

    inning_by_number = Map.new(innings, fn inning -> {inning.inning_number, inning} end)

    find_phase(game, inning_by_number, inning_runs, 1)
  end

  defp find_phase(game, inning_by_number, inning_runs, inning) when inning > @max_innings do
    side = game.home_or_away || "away"
    game_over_phase(side, inning_by_number, inning_runs)
  end

  defp find_phase(game, inning_by_number, inning_runs, inning) do
    side = game.home_or_away || "away"
    our = Map.get(inning_runs, inning, %{outs: 0, runs: 0})
    opp = Map.get(inning_by_number, inning, %{opp_runs: 0, opp_outs: 0})

    our_complete? = our.outs >= 3 or our.runs >= 5
    opp_complete? = opp.opp_outs >= 3 or opp.opp_runs >= 5

    case phase_decision(side, inning, our_complete?, opp_complete?, home_team_ahead?(game)) do
      {:phase, half, mode} ->
        phase_data(side, inning_by_number, inning_runs, inning, half, mode)

      :game_over ->
        game_over_phase(side, inning_by_number, inning_runs)

      :next_inning ->
        find_phase(game, inning_by_number, inning_runs, inning + 1)
    end
  end

  defp phase_decision("away", _inning, false, _opp_complete?, _home_ahead?),
    do: {:phase, :top, :offense}

  defp phase_decision("away", inning, true, _opp_complete?, true) when inning == @max_innings,
    do: :game_over

  defp phase_decision("away", _inning, true, false, _home_ahead?),
    do: {:phase, :bottom, :defense}

  defp phase_decision("away", _inning, true, true, _home_ahead?),
    do: :next_inning

  defp phase_decision("home", _inning, _our_complete?, false, _home_ahead?),
    do: {:phase, :top, :defense}

  defp phase_decision("home", inning, _our_complete?, true, true) when inning == @max_innings,
    do: :game_over

  defp phase_decision("home", _inning, false, true, _home_ahead?),
    do: {:phase, :bottom, :offense}

  defp phase_decision("home", _inning, true, true, _home_ahead?),
    do: :next_inning

  defp phase_data(side, inning_by_number, inning_runs, inning, half, mode) do
    our = Map.get(inning_runs, inning, %{outs: 0, runs: 0})
    opp = Map.get(inning_by_number, inning, %{opp_runs: 0, opp_outs: 0})

    %{
      inning: inning,
      half: half,
      mode: mode,
      side: side,
      our_outs: min(our.outs, 3),
      our_runs: our.runs,
      opp_outs: min(opp.opp_outs || 0, 3),
      opp_runs: opp.opp_runs || 0
    }
  end

  defp game_over_phase(side, inning_by_number, inning_runs) do
    phase_data(side, inning_by_number, inning_runs, @max_innings, :final, :game_over)
  end

  defp home_team_ahead?(game) do
    {home_score, away_score} =
      if game.home_or_away == "home" do
        {game.our_score, game.opp_score}
      else
        {game.opp_score, game.our_score}
      end

    home_score > away_score
  end

  defp home_run_counts(game),
    do: %{home: game.home_home_runs || 0, away: game.away_home_runs || 0}

  defp our_hr_increment_attrs(game, delta) do
    if game.home_or_away == "home" do
      %{home_home_runs: max((game.home_home_runs || 0) + delta, 0)}
    else
      %{away_home_runs: max((game.away_home_runs || 0) + delta, 0)}
    end
  end

  defp opponent_hr_increment_attrs(game) do
    if game.home_or_away == "home" do
      %{away_home_runs: (game.away_home_runs || 0) + 1}
    else
      %{home_home_runs: (game.home_home_runs || 0) + 1}
    end
  end

  defp home_run_rule_violation?(game, team) do
    counts = home_run_counts(game)

    next_counts =
      case team do
        :our_team ->
          if game.home_or_away == "home" do
            %{counts | home: counts.home + 1}
          else
            %{counts | away: counts.away + 1}
          end

        :opponent ->
          if game.home_or_away == "home" do
            %{counts | away: counts.away + 1}
          else
            %{counts | home: counts.home + 1}
          end
      end

    abs(next_counts.home - next_counts.away) > 2
  end

  defp result_requires_confirmation?(result, bases) do
    result in ["single", "double", "triple", "out"] and base_occupied?(bases)
  end

  defp base_occupied?(bases),
    do: not is_nil(bases.first) or not is_nil(bases.second) or not is_nil(bases.third)

  @plan_cycle [:first, :second, :third, :home, :out]
  defp destination_options, do: @plan_cycle

  defp open_result_modal(socket, result) do
    default_plan = default_runner_plan_for_result(result)

    socket
    |> assign(:result_modal_open, true)
    |> assign(:pending_result, result)
    |> assign(:modal_runner_plan, default_plan)
    |> assign(:modal_error, nil)
  end

  defp default_runner_plan_for_result(result) do
    %{
      first: auto_destination(:first, result),
      second: auto_destination(:second, result),
      third: auto_destination(:third, result),
      batter: auto_destination(:batter, result)
    }
  end

  defp derive_bases(game_id) do
    Tracking.list_plate_appearances(game_id)
    |> Enum.sort_by(& &1.sequence_number)
    |> Enum.reduce(empty_bases(), fn appearance, bases ->
      next_bases_for_appearance(appearance, bases)
    end)
  end

  defp apply_result_to_bases(bases, result, batter_id) do
    apply_result_to_bases(bases, result, batter_id, default_runner_plan())
  end

  defp apply_result_to_bases(bases, result, batter_id, runner_plan) do
    actors = [
      {:first, bases.first},
      {:second, bases.second},
      {:third, bases.third},
      {:batter, batter_id}
    ]

    case Enum.reduce_while(actors, {empty_bases(), 0}, fn actor_and_player, acc ->
           reduce_runner(actor_and_player, acc, result, runner_plan)
         end) do
      {:error, :base_conflict} ->
        {:error, :base_conflict}

      {next_bases, runs} ->
        rbis = if result == "strikeout", do: 0, else: runs
        {:ok, next_bases, runs, rbis}
    end
  end

  defp reduce_runner({_actor, nil}, {next_bases, runs}, _result, _runner_plan),
    do: {:cont, {next_bases, runs}}

  defp reduce_runner({actor, player_id}, {next_bases, runs}, result, runner_plan) do
    destination = planned_destination(actor, result, runner_plan)
    apply_runner_destination(next_bases, runs, player_id, destination)
  end

  defp apply_runner_destination(next_bases, runs, _player_id, :out),
    do: {:cont, {next_bases, runs}}

  defp apply_runner_destination(next_bases, runs, _player_id, :home),
    do: {:cont, {next_bases, runs + 1}}

  defp apply_runner_destination(next_bases, runs, player_id, destination)
       when destination in [:first, :second, :third] do
    if Map.get(next_bases, destination) do
      {:halt, {:error, :base_conflict}}
    else
      {:cont, {Map.put(next_bases, destination, player_id), runs}}
    end
  end

  defp planned_destination(actor, result, runner_plan) do
    case Map.get(runner_plan, actor, :auto) do
      :auto -> auto_destination(actor, result)
      destination -> destination
    end
  end

  defp auto_destination(:batter, "single"), do: :first
  defp auto_destination(:batter, "double"), do: :second
  defp auto_destination(:batter, "triple"), do: :third
  defp auto_destination(:batter, "home_run"), do: :home
  defp auto_destination(:batter, "walk"), do: :first
  defp auto_destination(:batter, "strikeout"), do: :out
  defp auto_destination(:batter, "out"), do: :out

  defp auto_destination(:first, "single"), do: :second
  defp auto_destination(:first, "double"), do: :third
  defp auto_destination(:first, "triple"), do: :home
  defp auto_destination(:first, "home_run"), do: :home
  defp auto_destination(:first, "walk"), do: :second
  defp auto_destination(:first, "strikeout"), do: :first
  defp auto_destination(:first, "out"), do: :first

  defp auto_destination(:second, "single"), do: :third
  defp auto_destination(:second, "double"), do: :home
  defp auto_destination(:second, "triple"), do: :home
  defp auto_destination(:second, "home_run"), do: :home
  defp auto_destination(:second, "walk"), do: :second
  defp auto_destination(:second, "strikeout"), do: :second
  defp auto_destination(:second, "out"), do: :second

  defp auto_destination(:third, "single"), do: :home
  defp auto_destination(:third, "double"), do: :home
  defp auto_destination(:third, "triple"), do: :home
  defp auto_destination(:third, "home_run"), do: :home
  defp auto_destination(:third, "walk"), do: :home
  defp auto_destination(:third, "strikeout"), do: :third
  defp auto_destination(:third, "out"), do: :third
  defp auto_destination(_actor, _result), do: :out

  defp end_bases_from_record(nil), do: nil

  defp end_bases_from_record(end_bases) do
    %{
      first: map_base(end_bases, :first),
      second: map_base(end_bases, :second),
      third: map_base(end_bases, :third)
    }
  end

  defp map_base(map, base) do
    Map.get(map, base) || Map.get(map, Atom.to_string(base))
  end

  defp serialize_bases(bases), do: %{first: bases.first, second: bases.second, third: bases.third}

  defp build_feed(game_id) do
    name_by_player_id =
      Tracking.list_players()
      |> Map.new(fn player -> {player.id, player.name} end)

    {_, feed} =
      Tracking.list_plate_appearances(game_id)
      |> Enum.sort_by(& &1.sequence_number)
      |> Enum.reduce({empty_bases(), []}, fn appearance, {bases, events} ->
        {end_bases, event} = event_for_appearance(appearance, bases, name_by_player_id)
        {end_bases, [event | events]}
      end)

    Enum.take(feed, 15)
  end

  defp scoring_player_ids_for_feed(bases, end_bases, appearance) do
    ending_ids = [end_bases.first, end_bases.second, end_bases.third]

    displaced_runners =
      [bases.third, bases.second, bases.first]
      |> Enum.reject(&(is_nil(&1) or &1 in ending_ids))

    batter_id = appearance.player_id

    scorer_candidates =
      if batter_can_score_for_feed?(appearance.result) and batter_id not in ending_ids do
        displaced_runners ++ [batter_id]
      else
        displaced_runners
      end

    scorer_candidates
    |> Enum.uniq()
    |> Enum.take(max(appearance.runs_scored, 0))
  end

  defp batter_can_score_for_feed?(result),
    do: result in ["single", "double", "triple", "home_run", "walk"]

  defp next_bases_for_appearance(%{skip: true}, bases), do: bases

  defp next_bases_for_appearance(appearance, bases) do
    case end_bases_from_record(appearance.end_bases) do
      nil ->
        case apply_result_to_bases(bases, appearance.result, appearance.player_id) do
          {:ok, next_bases, _runs, _rbis} -> next_bases
          {:error, :base_conflict} -> bases
        end

      end_bases ->
        end_bases
    end
  end

  defp event_for_appearance(%{skip: true} = appearance, bases, _name_by_player_id) do
    event = %{type: :skip, player_name: appearance.player.name, inning: appearance.inning}
    {bases, event}
  end

  defp event_for_appearance(appearance, bases, name_by_player_id) do
    end_bases = next_bases_for_appearance(appearance, bases)

    scorer_names =
      scoring_player_ids_for_feed(bases, end_bases, appearance)
      |> Enum.map(fn player_id ->
        Map.get(name_by_player_id, player_id, "Player ##{player_id}")
      end)

    event = %{
      type: :pa,
      player_name: appearance.player.name,
      result: appearance.result,
      balls: appearance.balls || 0,
      strikes: appearance.strikes || 0,
      runs_scored: appearance.runs_scored,
      rbis: appearance.rbis,
      inning: appearance.inning,
      inserted_batter: appearance.inserted_batter,
      scorer_names: scorer_names
    }

    {end_bases, event}
  end

  defp parse_game_id(%{"id" => id}) do
    case Integer.parse(id) do
      {game_id, _} -> game_id
      :error -> fallback_game_id()
    end
  end

  defp parse_game_id(_), do: fallback_game_id()

  defp fallback_game_id do
    case Tracking.list_games() do
      [game | _] -> game.id
      [] -> raise "No games available. Create a game first."
    end
  end

  defp reload_game_state(socket) do
    game = Tracking.get_game!(socket.assigns.game.id)
    innings = Tracking.ensure_innings(game.id)
    phase = derive_phase(game, innings, Tracking.list_plate_appearances(game.id))

    game =
      if phase.mode == :game_over and game.status != "final" do
        {:ok, updated_game} = Tracking.update_game(game, %{status: "final"})
        updated_game
      else
        game
      end

    socket
    |> assign(:game, game)
    |> assign(:innings, innings)
    |> assign(:phase, phase)
    |> assign(:our_score, game.our_score)
    |> assign(:opp_score, game.opp_score)
    |> assign(:feed, build_feed(game.id))
    |> assign(:bench_players, Tracking.list_bench_players(game.id))
    |> assign(:bases, derive_bases(game.id))
    |> assign(:result_modal_open, false)
    |> assign(:pending_result, nil)
    |> assign(:modal_runner_plan, default_runner_plan())
    |> assign(:modal_error, nil)
  end

  defp normalize_count_for_result("walk", _balls, strikes), do: {4, min(strikes, 2)}
  defp normalize_count_for_result("strikeout", balls, _strikes), do: {min(balls, 3), 3}
  defp normalize_count_for_result(_result, balls, strikes), do: {balls, strikes}

  defp record_result(socket, result, balls, strikes),
    do: record_result(socket, result, balls, strikes, default_runner_plan())

  defp record_result(socket, result, balls, strikes, runner_plan) do
    batter = inserted_or_current_batter(socket.assigns)
    game_counts = home_run_counts(socket.assigns.game)
    {normalized_balls, normalized_strikes} = normalize_count_for_result(result, balls, strikes)

    with :ok <- validate_home_run_limit(socket.assigns.game, result),
         {:ok, new_bases, auto_runs, auto_rbis} <-
           apply_result_to_bases(socket.assigns.bases, result, batter.id, runner_plan),
         {:ok, plate_appearance} <-
           record_plate_appearance_for_result(
             socket,
             batter,
             result,
             normalized_balls,
             normalized_strikes,
             auto_runs,
             auto_rbis,
             new_bases
           ),
         :ok <- maybe_increment_our_team_home_runs(socket.assigns.game, result) do
      socket
      |> push_undo_event(%{
        type: :pa,
        plate_appearance_id: plate_appearance.id,
        home_home_runs: game_counts.home,
        away_home_runs: game_counts.away
      })
      |> reload_game_state()
      |> next_batter()
      |> assign(:selected_result, result)
      |> assign(:balls, 0)
      |> assign(:strikes, 0)
      |> assign(:inserted_player, nil)
    else
      {:error, :home_run_limit} ->
        socket
        |> assign(:modal_error, "Home run cap reached: home/away HR difference cannot exceed 2.")
        |> put_flash(:error, "Home run cap reached: home/away HR difference cannot exceed 2.")

      {:error, :base_conflict} ->
        assign(
          socket,
          :modal_error,
          "Runner destinations conflict. Two runners cannot finish on the same base."
        )
    end
  end

  defp validate_home_run_limit(game, "home_run") do
    if home_run_rule_violation?(game, :our_team), do: {:error, :home_run_limit}, else: :ok
  end

  defp validate_home_run_limit(_game, _result), do: :ok

  defp record_plate_appearance_for_result(
         socket,
         batter,
         result,
         normalized_balls,
         normalized_strikes,
         auto_runs,
         auto_rbis,
         new_bases
       ) do
    Tracking.record_plate_appearance(%{
      game_id: socket.assigns.game.id,
      player_id: batter.id,
      inning: socket.assigns.phase.inning,
      result: result,
      balls: normalized_balls,
      strikes: normalized_strikes,
      runs_scored: auto_runs,
      rbis: auto_rbis,
      skip: false,
      inserted_batter: not is_nil(socket.assigns.inserted_player),
      end_bases: serialize_bases(new_bases)
    })
  end

  defp maybe_increment_our_team_home_runs(game, "home_run") do
    case Tracking.update_game(game, our_hr_increment_attrs(game, 1)) do
      {:ok, _game} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_increment_our_team_home_runs(_game, _result), do: :ok

  defp base_runner_name(_assigns, nil), do: "Empty"

  defp base_runner_name(assigns, player_id) do
    (assigns.lineup ++ assigns.bench_players)
    |> Enum.find(&(&1.id == player_id))
    |> case do
      nil -> "Player ##{player_id}"
      player -> "##{player.jersey_number} #{player.name}"
    end
  end

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign(:current_batter, current_batter(assigns))
      |> assign(:effective_batter, inserted_or_current_batter(assigns))

    {_preview_bases, preview_runs, preview_rbis} =
      case apply_result_to_bases(
             assigns.bases,
             assigns.selected_result,
             assigns.effective_batter.id
           ) do
        {:ok, next_bases, runs, rbis} -> {next_bases, runs, rbis}
        {:error, :base_conflict} -> {assigns.bases, 0, 0}
      end

    {modal_preview_bases, modal_preview_runs, modal_preview_rbis, modal_preview_conflict?} =
      if assigns.result_modal_open && not is_nil(assigns.pending_result) do
        case apply_result_to_bases(
               assigns.bases,
               assigns.pending_result,
               assigns.effective_batter.id,
               assigns.modal_runner_plan
             ) do
          {:ok, next_bases, runs, rbis} -> {next_bases, runs, rbis, false}
          {:error, :base_conflict} -> {assigns.bases, 0, 0, true}
        end
      else
        {assigns.bases, 0, 0, false}
      end

    assigns =
      assigns
      |> assign(:preview_runs, preview_runs)
      |> assign(:preview_rbis, preview_rbis)
      |> assign(:modal_preview_bases, modal_preview_bases)
      |> assign(:modal_preview_runs, modal_preview_runs)
      |> assign(:modal_preview_rbis, modal_preview_rbis)
      |> assign(:modal_preview_conflict?, modal_preview_conflict?)

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="score-shell mx-auto w-full max-w-5xl space-y-4 pb-24">
        <.app_tabs current={:scoring} score_path={~p"/games/#{@game.id}/scoring"} />

        <section class="score-card sticky top-3 z-20 space-y-3 rounded-3xl px-4 py-4 text-white shadow-xl shadow-blue-950/20 sm:px-6">
          <div class="flex items-center justify-between gap-3">
            <div>
              <p class="text-xs uppercase tracking-[0.18em] text-cyan-100">Slo-Pitch Live</p>
              <h1 class="text-xl font-semibold sm:text-2xl">vs {@game.opponent_name}</h1>
              <p class="text-xs text-blue-100 sm:text-sm">
                {Calendar.strftime(@game.played_on, "%b %d, %Y")} • {@game.location}
              </p>
            </div>
            <div class="rounded-2xl bg-white/15 px-4 py-3 text-right backdrop-blur">
              <p class="text-xs uppercase tracking-[0.2em] text-cyan-100">Score</p>
              <p class="text-2xl font-bold sm:text-3xl">{@our_score} - {@opp_score}</p>
              <p class="text-xs text-blue-100">
                {String.capitalize(Atom.to_string(@phase.half))} {@phase.inning} • {if @phase.mode ==
                                                                                         :offense,
                                                                                       do:
                                                                                         "Our At-Bat",
                                                                                       else:
                                                                                         if(
                                                                                           @phase.mode ==
                                                                                             :defense,
                                                                                           do:
                                                                                             "Opponent At-Bat",
                                                                                           else:
                                                                                             "Game Final"
                                                                                         )}
              </p>
              <p class="text-xs text-blue-100">
                HR Home {@game.home_home_runs} • Away {@game.away_home_runs}
              </p>
            </div>
          </div>

          <div class="flex flex-wrap gap-2">
            <button
              id="skip-batter-button"
              phx-click="skip_batter"
              disabled={@phase.mode != :offense}
              class="soft-pill"
            >
              <.icon name="hero-forward" class="size-4" /> Skip
            </button>
            <button
              id="insert-batter-button"
              phx-click="open_insert_picker"
              disabled={@phase.mode != :offense}
              class="soft-pill"
            >
              <.icon name="hero-user-plus" class="size-4" /> Insert Batter
            </button>
            <button id="undo-last-button" phx-click="undo_last" class="soft-pill">
              <.icon name="hero-arrow-uturn-left" class="size-4" /> Undo
            </button>
            <button
              id="reset-game-state-button"
              phx-click="reset_game_state"
              phx-confirm="Reset all tracked scoring, opponent runs/outs, and plate appearances for this game?"
              class="soft-pill"
            >
              <.icon name="hero-arrow-path" class="size-4" /> Reset Game
            </button>
            <.link navigate={~p"/games/#{@game.id}"} class="soft-pill">
              <.icon name="hero-clipboard-document-list" class="size-4" /> Summary
            </.link>
          </div>
        </section>

        <section class="grid gap-4 lg:grid-cols-[1.6fr_1fr]">
          <div :if={@phase.mode == :offense} class="space-y-4">
            <article
              :if={@phase.mode == :offense}
              class="rounded-3xl border border-blue-100 bg-white p-4 shadow-sm sm:p-6"
            >
              <div class="flex items-start justify-between gap-4">
                <div>
                  <p class="text-xs uppercase tracking-[0.2em] text-slate-500">Now Batting</p>
                  <h2 class="mt-1 text-2xl font-semibold text-slate-900">
                    #{@effective_batter.jersey_number} {@effective_batter.name}
                  </h2>
                  <p class="mt-1 text-sm text-slate-500">
                    Spot {@batting_index + 1} of {length(@lineup)}
                    <span
                      :if={@inserted_player}
                      class="ml-2 rounded-full bg-amber-100 px-2 py-0.5 text-xs font-semibold text-amber-800"
                    >
                      Inserted Batter
                    </span>
                  </p>
                </div>
                <div class="rounded-2xl bg-slate-100 px-3 py-2 text-right">
                  <p class="text-xs uppercase tracking-[0.2em] text-slate-500">Result / Count</p>
                  <p class="text-lg font-semibold text-slate-900">{result_label(@selected_result)}</p>
                  <p class="text-sm font-semibold text-slate-600">{@balls}-{@strikes}</p>
                  <p class="text-xs text-slate-500">
                    Projected R {@preview_runs} • RBI {@preview_rbis}
                  </p>
                </div>
              </div>
            </article>

            <article
              :if={@phase.mode == :offense}
              class="rounded-3xl border border-blue-100 bg-white p-4 shadow-sm sm:p-6"
            >
              <h3 class="text-xs font-semibold uppercase tracking-[0.2em] text-slate-500">
                Plate Appearance
              </h3>
              <p class="mt-2 text-xs text-slate-500">
                <%= if @phase.mode == :offense do %>
                  Active: {String.capitalize(Atom.to_string(@phase.half))} {@phase.inning} • Outs {@phase.our_outs}/3 • Runs this half {@phase.our_runs}/5
                <% else %>
                  Waiting for opponent half to finish.
                <% end %>
              </p>

              <div class="mt-3 grid grid-cols-3 gap-2">
                <button
                  id="pitch-ball-button"
                  phx-click="record_ball"
                  disabled={@phase.mode != :offense}
                  class="min-h-11 rounded-xl border border-blue-200 bg-blue-50 px-3 text-sm font-semibold text-blue-900 transition hover:bg-blue-100"
                >
                  Ball
                </button>
                <button
                  id="pitch-strike-button"
                  phx-click="record_strike"
                  disabled={@phase.mode != :offense}
                  class="min-h-11 rounded-xl border border-rose-200 bg-rose-50 px-3 text-sm font-semibold text-rose-900 transition hover:bg-rose-100"
                >
                  Strike (Foul)
                </button>
                <button
                  id="pitch-reset-button"
                  phx-click="reset_count"
                  disabled={@phase.mode != :offense}
                  class="min-h-11 rounded-xl border border-slate-200 bg-slate-50 px-3 text-sm font-semibold text-slate-700 transition hover:bg-slate-100"
                >
                  Reset Count
                </button>
              </div>

              <div class="mt-3 grid grid-cols-2 gap-2 sm:grid-cols-5">
                <button
                  :for={result <- @results}
                  phx-click="select_result"
                  phx-value-result={result.value}
                  disabled={@phase.mode != :offense}
                  class={[
                    "result-pill min-h-14 rounded-2xl text-base font-semibold text-white transition",
                    result.color,
                    @selected_result == result.value && "ring-4 ring-blue-200"
                  ]}
                >
                  {result.label}
                </button>
              </div>
            </article>

            <article
              :if={@phase.mode == :offense}
              class="rounded-3xl border border-blue-100 bg-white p-4 shadow-sm sm:p-6"
            >
              <div class="flex items-center justify-between gap-3">
                <h3 class="text-xs font-semibold uppercase tracking-[0.2em] text-slate-500">
                  Recent Events
                </h3>
                <span class="rounded-full bg-slate-100 px-2.5 py-1 text-xs font-medium text-slate-700">
                  {length(@feed)} tracked
                </span>
              </div>
              <div class="mt-3 space-y-2">
                <div
                  :for={event <- @feed}
                  class="rounded-2xl border border-slate-200 bg-slate-50 px-3 py-2"
                >
                  <%= if event.type == :skip do %>
                    <p class="text-sm font-semibold text-slate-700">{event.player_name} skipped</p>
                    <p class="text-xs text-slate-500">Inning {event.inning}</p>
                  <% else %>
                    <div class="flex items-center justify-between gap-3">
                      <p class="text-sm font-semibold text-slate-900">{event.player_name}</p>
                      <p class="text-xs font-semibold uppercase tracking-[0.16em] text-slate-500">
                        {result_label(event.result)}
                      </p>
                    </div>
                    <p class="text-xs text-slate-500">
                      Inning {event.inning} • Count {event.balls}-{event.strikes} • RBI {event.rbis}
                      <span :if={event.scorer_names != []}>
                        • Scored {Enum.join(event.scorer_names, ", ")}
                      </span>
                      <span :if={event.inserted_batter}>• Inserted</span>
                    </p>
                  <% end %>
                </div>
              </div>
            </article>
          </div>

          <div :if={@phase.mode == :offense} class="space-y-4">
            <article
              :if={@phase.mode == :offense}
              class="rounded-3xl border border-blue-100 bg-white p-4 shadow-sm sm:p-6"
            >
              <div class="flex items-center justify-between gap-3">
                <h3 class="text-xs font-semibold uppercase tracking-[0.2em] text-slate-500">Bases</h3>
                <button
                  phx-click="reset_bases"
                  class="rounded-xl border border-slate-200 bg-slate-50 px-3 py-1.5 text-xs font-semibold text-slate-700 hover:bg-slate-100"
                >
                  Reset Bases
                </button>
              </div>

              <div class="mt-3 space-y-2">
                <div class="rounded-xl border border-slate-200 bg-slate-50 px-3 py-2">
                  <div class="flex items-center justify-between gap-2">
                    <p class="text-xs uppercase tracking-[0.16em] text-slate-500">First</p>
                    <button
                      phx-click="clear_base"
                      phx-value-base="first"
                      class="text-xs font-semibold text-rose-700 hover:text-rose-900"
                    >
                      Clear
                    </button>
                  </div>
                  <p class="text-sm font-semibold text-slate-900">
                    {base_runner_name(assigns, @bases.first)}
                  </p>
                </div>
                <div class="rounded-xl border border-slate-200 bg-slate-50 px-3 py-2">
                  <div class="flex items-center justify-between gap-2">
                    <p class="text-xs uppercase tracking-[0.16em] text-slate-500">Second</p>
                    <button
                      phx-click="clear_base"
                      phx-value-base="second"
                      class="text-xs font-semibold text-rose-700 hover:text-rose-900"
                    >
                      Clear
                    </button>
                  </div>
                  <p class="text-sm font-semibold text-slate-900">
                    {base_runner_name(assigns, @bases.second)}
                  </p>
                </div>
                <div class="rounded-xl border border-slate-200 bg-slate-50 px-3 py-2">
                  <div class="flex items-center justify-between gap-2">
                    <p class="text-xs uppercase tracking-[0.16em] text-slate-500">Third</p>
                    <button
                      phx-click="clear_base"
                      phx-value-base="third"
                      class="text-xs font-semibold text-rose-700 hover:text-rose-900"
                    >
                      Clear
                    </button>
                  </div>
                  <p class="text-sm font-semibold text-slate-900">
                    {base_runner_name(assigns, @bases.third)}
                  </p>
                </div>
              </div>
            </article>

            <article
              :if={@phase.mode == :offense}
              class="rounded-3xl border border-blue-100 bg-white p-4 shadow-sm sm:p-6"
            >
              <h3 class="text-xs font-semibold uppercase tracking-[0.2em] text-slate-500">Lineup</h3>
              <ol class="mt-3 space-y-2">
                <li
                  :for={{player, index} <- Enum.with_index(@lineup)}
                  class={[
                    "flex items-center justify-between rounded-xl px-3 py-2",
                    @batting_index == index && is_nil(@inserted_player) && "bg-blue-100 text-blue-950",
                    @batting_index != index && "bg-slate-50 text-slate-700"
                  ]}
                >
                  <div class="flex items-center gap-2">
                    <span class="text-xs font-semibold uppercase tracking-[0.16em] text-slate-500">
                      {index + 1}
                    </span>
                    <span class="font-semibold">#{player.jersey_number} {player.name}</span>
                  </div>
                  <.icon
                    :if={@batting_index == index && is_nil(@inserted_player)}
                    name="hero-arrow-right-circle"
                    class="size-4"
                  />
                </li>
              </ol>
            </article>
          </div>

          <article
            :if={@phase.mode == :defense}
            class="col-span-full rounded-3xl border border-blue-100 bg-white p-5 shadow-sm sm:p-7"
          >
            <div class="flex items-center justify-between gap-3">
              <h3 class="text-sm font-semibold uppercase tracking-[0.2em] text-slate-500">
                Opponent Runs
              </h3>
              <p class="text-sm font-semibold text-slate-700">
                {String.capitalize(Atom.to_string(@phase.half))} {@phase.inning}
              </p>
            </div>

            <div class="mt-4 rounded-2xl bg-slate-50 p-4">
              <div class="grid gap-3 sm:grid-cols-2">
                <div class="rounded-xl border border-slate-200 bg-white px-4 py-3">
                  <p class="text-xs uppercase tracking-[0.2em] text-slate-500">Runs</p>
                  <p class="mt-1 text-3xl font-bold text-slate-900">{@phase.opp_runs}</p>
                </div>
                <div class="rounded-xl border border-slate-200 bg-white px-4 py-3">
                  <p class="text-xs uppercase tracking-[0.2em] text-slate-500">Outs</p>
                  <p class="mt-1 text-3xl font-bold text-slate-900">{@phase.opp_outs}</p>
                </div>
              </div>

              <div class="mt-4 grid grid-cols-2 gap-3">
                <button
                  phx-click="inc_opp_runs"
                  class="inline-flex min-h-16 items-center justify-center rounded-2xl bg-emerald-600 px-4 text-lg font-bold text-white shadow-sm transition hover:bg-emerald-700 active:scale-[0.99]"
                >
                  + Run
                </button>
                <button
                  phx-click="inc_opp_outs"
                  class="inline-flex min-h-16 items-center justify-center rounded-2xl bg-rose-600 px-4 text-lg font-bold text-white shadow-sm transition hover:bg-rose-700 active:scale-[0.99]"
                >
                  + Out
                </button>
              </div>
              <button
                phx-click="inc_opp_home_run"
                class="mt-3 inline-flex min-h-14 w-full items-center justify-center rounded-2xl bg-amber-500 px-4 text-lg font-bold text-white shadow-sm transition hover:bg-amber-600 active:scale-[0.99]"
              >
                + Home Run
              </button>

              <p class="mt-3 text-xs text-slate-500">
                Runs / 5 and Outs / 3 auto-transition halves.
              </p>
            </div>
          </article>
        </section>
      </div>

      <div
        :if={@result_modal_open}
        class="fixed inset-0 z-40 flex items-end bg-slate-900/60 p-3 sm:items-center sm:justify-center"
        phx-click="close_result_modal"
      >
        <div
          class="w-full max-w-lg rounded-3xl bg-white p-4 shadow-xl sm:p-6"
          phx-click-away="close_result_modal"
        >
          <div class="flex items-start justify-between gap-3">
            <div>
              <p class="text-xs uppercase tracking-[0.2em] text-slate-500">Confirm Play</p>
              <h3 class="text-lg font-semibold text-slate-900">
                {result_label(@pending_result || @selected_result)}
              </h3>
              <p class="text-xs text-slate-500">
                Adjust destinations, then confirm this plate appearance.
              </p>
            </div>
            <button
              phx-click="close_result_modal"
              class="rounded-lg p-1 text-slate-500 hover:bg-slate-100"
            >
              <.icon name="hero-x-mark" class="size-5" />
            </button>
          </div>

          <p :if={@modal_error} class="mt-3 rounded-lg bg-rose-50 px-2 py-1 text-xs text-rose-700">
            {@modal_error}
          </p>

          <div class="mt-4 space-y-2">
            <div class="rounded-xl border border-slate-200 bg-slate-50 px-3 py-2">
              <p class="text-xs uppercase tracking-[0.16em] text-slate-500">Batter</p>
              <p class="mt-1 text-sm font-semibold text-slate-900">
                #{@effective_batter.jersey_number} {@effective_batter.name}
              </p>
              <div class="mt-2 flex flex-wrap gap-1.5">
                <button
                  :for={destination <- destination_options()}
                  phx-click="set_modal_runner_destination"
                  phx-value-runner="batter"
                  phx-value-destination={destination}
                  class={destination_button_classes(@modal_runner_plan.batter, destination)}
                >
                  {destination_label(destination)}
                </button>
              </div>
            </div>

            <div
              :if={!is_nil(@bases.first)}
              class="rounded-xl border border-slate-200 bg-slate-50 px-3 py-2"
            >
              <p class="text-xs uppercase tracking-[0.16em] text-slate-500">Runner on First</p>
              <p class="mt-1 text-sm font-semibold text-slate-900">
                {base_runner_name(assigns, @bases.first)}
              </p>
              <div class="mt-2 flex flex-wrap gap-1.5">
                <button
                  :for={destination <- destination_options()}
                  phx-click="set_modal_runner_destination"
                  phx-value-runner="first"
                  phx-value-destination={destination}
                  class={destination_button_classes(@modal_runner_plan.first, destination)}
                >
                  {destination_label(destination)}
                </button>
              </div>
            </div>

            <div
              :if={!is_nil(@bases.second)}
              class="rounded-xl border border-slate-200 bg-slate-50 px-3 py-2"
            >
              <p class="text-xs uppercase tracking-[0.16em] text-slate-500">Runner on Second</p>
              <p class="mt-1 text-sm font-semibold text-slate-900">
                {base_runner_name(assigns, @bases.second)}
              </p>
              <div class="mt-2 flex flex-wrap gap-1.5">
                <button
                  :for={destination <- destination_options()}
                  phx-click="set_modal_runner_destination"
                  phx-value-runner="second"
                  phx-value-destination={destination}
                  class={destination_button_classes(@modal_runner_plan.second, destination)}
                >
                  {destination_label(destination)}
                </button>
              </div>
            </div>

            <div
              :if={!is_nil(@bases.third)}
              class="rounded-xl border border-slate-200 bg-slate-50 px-3 py-2"
            >
              <p class="text-xs uppercase tracking-[0.16em] text-slate-500">Runner on Third</p>
              <p class="mt-1 text-sm font-semibold text-slate-900">
                {base_runner_name(assigns, @bases.third)}
              </p>
              <div class="mt-2 flex flex-wrap gap-1.5">
                <button
                  :for={destination <- destination_options()}
                  phx-click="set_modal_runner_destination"
                  phx-value-runner="third"
                  phx-value-destination={destination}
                  class={destination_button_classes(@modal_runner_plan.third, destination)}
                >
                  {destination_label(destination)}
                </button>
              </div>
            </div>
          </div>

          <div class="mt-4 rounded-xl bg-slate-50 px-3 py-2 text-xs text-slate-600">
            <p>
              Projected: R {@modal_preview_runs} • RBI {@modal_preview_rbis}
            </p>
            <p class="mt-1">
              End Bases: 1B {base_runner_name(assigns, @modal_preview_bases.first)} • 2B {base_runner_name(
                assigns,
                @modal_preview_bases.second
              )} • 3B {base_runner_name(assigns, @modal_preview_bases.third)}
            </p>
            <p :if={@modal_preview_conflict?} class="mt-1 text-amber-700">
              Conflict detected: two runners cannot finish on the same base.
            </p>
          </div>

          <div class="mt-4 flex items-center justify-end gap-2">
            <button
              phx-click="close_result_modal"
              class="rounded-xl border border-slate-200 bg-white px-4 py-2 text-sm font-semibold text-slate-700 hover:bg-slate-50"
            >
              Cancel
            </button>
            <button
              phx-click="confirm_result_modal"
              class="rounded-xl bg-blue-600 px-4 py-2 text-sm font-semibold text-white hover:bg-blue-700"
            >
              Confirm Result
            </button>
          </div>
        </div>
      </div>

      <div
        :if={@insert_picker_open}
        class="fixed inset-0 z-30 flex items-end bg-slate-900/50 p-3 sm:items-center sm:justify-center"
        phx-click="close_insert_picker"
      >
        <div
          class="w-full max-w-md rounded-3xl bg-white p-4 shadow-xl sm:p-6"
          phx-click-away="close_insert_picker"
        >
          <div class="flex items-start justify-between gap-3">
            <div>
              <p class="text-xs uppercase tracking-[0.2em] text-slate-500">Insert Batter</p>
              <h3 class="text-lg font-semibold text-slate-900">Choose a player for this turn</h3>
            </div>
            <button
              phx-click="close_insert_picker"
              class="rounded-lg p-1 text-slate-500 hover:bg-slate-100"
            >
              <.icon name="hero-x-mark" class="size-5" />
            </button>
          </div>

          <div class="mt-4 space-y-2">
            <button
              :for={player <- @bench_players}
              phx-click="pick_insert_batter"
              phx-value-player_id={player.id}
              class="flex w-full items-center justify-between rounded-xl border border-slate-200 px-3 py-2 text-left transition hover:border-blue-300 hover:bg-blue-50"
            >
              <span class="font-semibold text-slate-900">#{player.jersey_number} {player.name}</span>
              <.icon name="hero-arrow-right" class="size-4 text-slate-500" />
            </button>
          </div>
        </div>
      </div>

      <.app_nav current={:scoring} score_path={~p"/games/#{@game.id}/scoring"} />
    </Layouts.app>
    """
  end

  defp result_label(result) do
    case result do
      "single" -> "1B"
      "double" -> "2B"
      "triple" -> "3B"
      "home_run" -> "HR"
      "walk" -> "BB"
      "strikeout" -> "K"
      "out" -> "OUT"
      _ -> result
    end
  end

  defp destination_label(destination) do
    case destination do
      :auto -> "Auto"
      :first -> "1B"
      :second -> "2B"
      :third -> "3B"
      :home -> "Home"
      :out -> "Out"
      _ -> "Auto"
    end
  end

  defp destination_button_classes(selected_destination, destination) do
    [
      "rounded-lg border px-2 py-1 text-[11px] font-semibold transition",
      selected_destination == destination &&
        "border-blue-300 bg-blue-100 text-blue-900",
      selected_destination != destination &&
        "border-slate-200 bg-white text-slate-700 hover:bg-slate-100"
    ]
  end

  defp push_undo_event(socket, event) do
    assign(socket, :undo_history, [event | socket.assigns.undo_history])
  end
end
