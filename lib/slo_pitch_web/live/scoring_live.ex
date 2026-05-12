defmodule SloPitchWeb.ScoringLive do
  use SloPitchWeb, :live_view

  alias SloPitch.Tracking
  alias SloPitch.Tracking.GameRules

  @results [
    %{value: "single", label: "1B", color: "bg-emerald-500 hover:bg-emerald-600"},
    %{value: "double", label: "2B", color: "bg-green-500 hover:bg-green-600"},
    %{value: "triple", label: "3B", color: "bg-lime-500 hover:bg-lime-600"},
    %{value: "home_run", label: "HR", color: "bg-amber-500 hover:bg-amber-600"},
    %{value: "out", label: "OUT", color: "bg-zinc-600 hover:bg-zinc-700"}
  ]
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
     |> assign(:inserted_player, nil)
     |> assign_scoring_view_state()}
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
    {:noreply, socket |> assign(:bases, bases) |> assign_scoring_view_state()}
  end

  def handle_event("reset_bases", _params, socket) do
    {:noreply, socket |> assign(:bases, empty_bases()) |> assign_scoring_view_state()}
  end

  def handle_event(
        "set_modal_runner_destination",
        %{"runner" => runner, "destination" => destination},
        socket
      ) do
    runner_key = String.to_existing_atom(runner)
    destination_key = String.to_existing_atom(destination)
    updated = Map.put(socket.assigns.modal_runner_plan, runner_key, destination_key)

    {:noreply,
     socket
     |> assign(:modal_runner_plan, updated)
     |> assign(:modal_error, nil)
     |> assign_scoring_view_state()}
  end

  def handle_event("close_result_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:result_modal_open, false)
     |> assign(:pending_result, nil)
     |> assign(:modal_runner_plan, default_runner_plan())
     |> assign(:modal_error, nil)
     |> assign_scoring_view_state()}
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
     |> assign(:insert_picker_open, false)
     |> assign_scoring_view_state()}
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
     |> assign(:inserted_player, nil)
     |> assign_scoring_view_state()}
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

  defp empty_bases, do: GameRules.empty_bases()
  defp default_runner_plan, do: GameRules.default_runner_plan()

  defp derive_phase(game, innings, appearances),
    do: GameRules.derive_phase(game, innings, appearances)

  defp home_run_counts(game), do: GameRules.home_run_counts(game)
  defp our_hr_increment_attrs(game, delta), do: GameRules.our_hr_increment_attrs(game, delta)
  defp opponent_hr_increment_attrs(game), do: GameRules.opponent_hr_increment_attrs(game)
  defp home_run_rule_violation?(game, team), do: GameRules.home_run_rule_violation?(game, team)

  defp result_requires_confirmation?(result, bases),
    do: GameRules.result_requires_confirmation?(result, bases)

  defp destination_options, do: GameRules.destination_options()

  defp open_result_modal(socket, result) do
    default_plan = GameRules.default_runner_plan_for_result(result)

    socket
    |> assign(:result_modal_open, true)
    |> assign(:pending_result, result)
    |> assign(:modal_runner_plan, default_plan)
    |> assign(:modal_error, nil)
    |> assign_scoring_view_state()
  end

  defp derive_bases(game_id) do
    Tracking.list_plate_appearances(game_id)
    |> GameRules.derive_bases()
  end

  defp apply_result_to_bases(bases, result, batter_id) do
    GameRules.apply_result_to_bases(bases, result, batter_id)
  end

  defp apply_result_to_bases(bases, result, batter_id, runner_plan) do
    GameRules.apply_result_to_bases(bases, result, batter_id, runner_plan)
  end

  defp serialize_bases(bases), do: GameRules.serialize_bases(bases)

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

  defp scoring_player_ids_for_feed(bases, end_bases, appearance),
    do: GameRules.scoring_player_ids(bases, end_bases, appearance)

  defp next_bases_for_appearance(appearance, bases),
    do: GameRules.next_bases_for_appearance(appearance, bases)

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
    |> assign_scoring_view_state()
  end

  defp normalize_count_for_result(result, balls, strikes),
    do: GameRules.normalize_count_for_result(result, balls, strikes)

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
      |> assign_scoring_view_state()
    else
      {:error, :home_run_limit} ->
        socket
        |> assign(:modal_error, "Home run cap reached: home/away HR difference cannot exceed 2.")
        |> put_flash(:error, "Home run cap reached: home/away HR difference cannot exceed 2.")
        |> assign_scoring_view_state()

      {:error, :base_conflict} ->
        socket
        |> assign(
          :modal_error,
          "Runner destinations conflict. Two runners cannot finish on the same base."
        )
        |> assign_scoring_view_state()
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

  defp assign_scoring_view_state(socket) do
    no_lineup? = socket.assigns.lineup == []
    {current_batter, effective_batter} = batter_assigns(socket.assigns, no_lineup?)

    {_preview_bases, preview_runs, preview_rbis} =
      result_preview(socket.assigns, effective_batter)

    {modal_preview_bases, modal_preview_runs, modal_preview_rbis, modal_preview_conflict?} =
      modal_result_preview(socket.assigns, effective_batter)

    socket
    |> assign(:current_batter, current_batter)
    |> assign(:effective_batter, effective_batter)
    |> assign(:no_lineup?, no_lineup?)
    |> assign(:preview_runs, preview_runs)
    |> assign(:preview_rbis, preview_rbis)
    |> assign(:modal_preview_bases, modal_preview_bases)
    |> assign(:modal_preview_runs, modal_preview_runs)
    |> assign(:modal_preview_rbis, modal_preview_rbis)
    |> assign(:modal_preview_conflict?, modal_preview_conflict?)
  end

  defp batter_assigns(_assigns, true), do: {nil, nil}

  defp batter_assigns(assigns, false) do
    {current_batter(assigns), inserted_or_current_batter(assigns)}
  end

  defp result_preview(assigns, nil), do: {assigns.bases, 0, 0}

  defp result_preview(assigns, effective_batter) do
    case apply_result_to_bases(assigns.bases, assigns.selected_result, effective_batter.id) do
      {:ok, next_bases, runs, rbis} -> {next_bases, runs, rbis}
      {:error, :base_conflict} -> {assigns.bases, 0, 0}
    end
  end

  defp modal_result_preview(assigns, nil), do: {assigns.bases, 0, 0, false}

  defp modal_result_preview(%{result_modal_open: false} = assigns, _effective_batter) do
    {assigns.bases, 0, 0, false}
  end

  defp modal_result_preview(%{pending_result: nil} = assigns, _effective_batter) do
    {assigns.bases, 0, 0, false}
  end

  defp modal_result_preview(assigns, effective_batter) do
    case apply_result_to_bases(
           assigns.bases,
           assigns.pending_result,
           effective_batter.id,
           assigns.modal_runner_plan
         ) do
      {:ok, next_bases, runs, rbis} -> {next_bases, runs, rbis, false}
      {:error, :base_conflict} -> {assigns.bases, 0, 0, true}
    end
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
