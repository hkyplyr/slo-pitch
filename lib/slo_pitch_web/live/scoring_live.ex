defmodule SloPitchWeb.ScoringLive do
  alias SloPitch.Tracking.GameState.Bases
  use SloPitchWeb, :live_view

  alias SloPitch.GameEngine.Bases
  alias SloPitch.Tracking
  alias SloPitch.Tracking.Games
  alias SloPitch.Tracking.GameState
  alias SloPitch.Tracking.Player

  @results [
    %{value: :single, label: "1B", color: "bg-emerald-500 hover:bg-emerald-600"},
    %{value: :double, label: "2B", color: "bg-green-500 hover:bg-green-600"},
    %{value: :triple, label: "3B", color: "bg-lime-500 hover:bg-lime-600"},
    %{value: :home_run, label: "HR", color: "bg-amber-500 hover:bg-amber-600"},
    %{value: :out, label: "OUT", color: "bg-zinc-600 hover:bg-zinc-700"}
  ]

  @impl true
  def mount(%{"id" => game_id}, _session, socket) do
    game = Tracking.get_game!(game_id)
    game_state = Games.rebuild_game_state(game)

    {:ok,
     socket
     |> assign(:page_title, "Live Scoring")
     |> assign(:game, game)
     |> assign(:game_state, game_state)
     |> assign(:current_scope, nil)
     |> assign(:results, @results)
     |> assign(:result_modal_open, false)
     |> assign(:pending_result, nil)
     |> assign(:modal_runner_plan, default_runner_plan())
     |> assign(:modal_error, nil)
     |> assign(:feed, build_feed(game.id))
     |> assign_scoring_view_state()}
  end

  @impl true
  def handle_event("select_result", %{"result" => "home_run"}, socket) do
    if home_run_rule_violation?(socket.assigns.game_state) do
      {:noreply, put_flash(socket, :error, "Home run cap reached.")}
    else
      {:noreply, record_result(socket, :home_run)}
    end
  end

  def handle_event("select_result", %{"result" => result_str}, socket) do
    result = String.to_existing_atom(result_str)

    if result_requires_confirmation?(socket, result) do
      {:noreply, open_result_modal(socket, result)}
    else
      {:noreply, record_result(socket, result, default_runner_plan())}
    end
  end

  def handle_event("record_ball", _params, socket) do
    game_state = Games.record_pitch(socket.assigns.game.id, socket.assigns.game_state, :ball)
    {:noreply, assign(socket, :game_state, game_state)}
  end

  def handle_event("record_strike", _params, socket) do
    game_state = Games.record_pitch(socket.assigns.game.id, socket.assigns.game_state, :strike)
    {:noreply, assign(socket, :game_state, game_state)}
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
    result = socket.assigns.pending_result

    {:noreply,
     socket
     |> record_result(
       result,
       socket.assigns.modal_runner_plan
     )
     |> assign(:result_modal_open, false)}
  end

  def handle_event("increment_runs", _params, socket) do
    game_state = Games.record_opponent(socket.assigns.game.id, socket.assigns.game_state, :run)
    {:noreply, assign(socket, :game_state, game_state)}
  end

  def handle_event("increment_home_runs", _params, socket) do
    if home_run_rule_violation?(socket.assigns.game_state) do
      {:noreply, put_flash(socket, :error, "Home run cap reached.")}
    else
      game_state =
        Games.record_opponent(socket.assigns.game.id, socket.assigns.game_state, :home_run)

      {:noreply, assign(socket, :game_state, game_state)}
    end
  end

  def handle_event("increment_outs", _params, socket) do
    game_state = Games.record_opponent(socket.assigns.game.id, socket.assigns.game_state, :out)
    {:noreply, assign(socket, :game_state, game_state)}
  end

  def handle_event("skip_batter", _params, socket) do
    game_state =
      Games.record_plate_appearance(
        socket.assigns.game.id,
        socket.assigns.game_state,
        :skip,
        default_runner_plan()
      )

    {:noreply, assign(socket, :game_state, game_state)}
  end

  def handle_event("undo_last", _params, socket) do
    game_state = Games.undo_last_event(socket.assigns.game)
    {:noreply, assign(socket, :game_state, game_state)}
  end

  defp default_runner_plan, do: Bases.default_runner_plan()

  @destination_options [:first, :second, :third, :home, :out]
  defp destination_options, do: @destination_options

  defp open_result_modal(socket, result) do
    default_plan = Bases.default_runner_plan_for_result(result)

    socket
    |> assign(:result_modal_open, true)
    |> assign(:pending_result, result)
    |> assign(:modal_runner_plan, default_plan)
    |> assign(:modal_error, nil)
    |> assign_scoring_view_state()
  end

  defp build_feed(_game_id), do: []

  defp record_result(socket, result, runner_plan \\ default_runner_plan()) do
    game_state =
      Games.record_plate_appearance(
        socket.assigns.game.id,
        socket.assigns.game_state,
        result,
        runner_plan
      )

    assign(socket, :game_state, game_state)
  end

  defp assign_scoring_view_state(socket) do
    {modal_preview_bases, modal_preview_runs, modal_preview_outs, modal_preview_conflict?} =
      modal_result_preview(socket.assigns, GameState.current_batter(socket.assigns.game_state))

    socket
    |> assign(:modal_preview_bases, modal_preview_bases)
    |> assign(:modal_preview_runs, length(modal_preview_runs))
    |> assign(:modal_preview_outs, length(modal_preview_outs))
    |> assign(:modal_preview_conflict?, modal_preview_conflict?)
  end

  defp modal_result_preview(assigns, nil), do: {assigns.game_state.bases, 0, 0, false}

  defp modal_result_preview(%{result_modal_open: false} = assigns, _effective_batter) do
    {assigns.game_state.bases, [], [], false}
  end

  defp modal_result_preview(%{pending_result: nil} = assigns, _effective_batter) do
    {assigns.game_state.bases, [], [], false}
  end

  defp modal_result_preview(assigns, effective_batter) do
    case Bases.apply_result_to_bases(
           assigns.game_state.bases,
           assigns.pending_result,
           effective_batter.id,
           assigns.modal_runner_plan
         ) do
      {:ok, next_bases, runs, rbis} -> {next_bases, runs, rbis, false}
      {:error, :base_conflict} -> {assigns.game_state.bases, [], [], true}
    end
  end

  defp result_label(result) do
    case result do
      :single -> "1B"
      :double -> "2B"
      :triple -> "3B"
      :home_run -> "HR"
      :walk -> "BB"
      :strikeout -> "K"
      :out -> "OUT"
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

  @confirmation_results ~w(single double triple out)a
  defp result_requires_confirmation?(socket, result) do
    result in @confirmation_results and GameState.Bases.occupied?(socket.assigns.game_state.bases)
  end

  def home_run_rule_violation?(%GameState{half: :top, home_runs: home_runs}),
    do: abs(home_runs.away + 1 - home_runs.home) > 2

  def home_run_rule_violation?(%GameState{half: :bottom, inning: 7, home_runs: home_runs}),
    do: home_runs.home + 1 > home_runs.away

  def home_run_rule_violation?(%GameState{half: :bottom, home_runs: home_runs}),
    do: abs(home_runs.home + 1 - home_runs.away) > 2
end
