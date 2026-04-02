defmodule SloPitchWeb.GamesLive.Setup do
  use SloPitchWeb, :live_view

  alias SloPitch.Tracking

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    game_id = String.to_integer(id)

    {:ok,
     socket
     |> assign(:page_title, "Lineup Setup")
     |> assign(:current_scope, nil)
     |> assign(:game, Tracking.get_game!(game_id))
     |> assign(:lineup, Tracking.list_lineup_players(game_id))
     |> assign(:bench_players, Tracking.list_bench_players(game_id))}
  end

  @impl true
  def handle_event("move_up", %{"index" => index}, socket) do
    index = String.to_integer(index)
    lineup = move(socket.assigns.lineup, index, index - 1)

    {:ok, _slots} = Tracking.set_game_lineup(socket.assigns.game.id, Enum.map(lineup, & &1.id))
    {:noreply, assign(socket, :lineup, Tracking.list_lineup_players(socket.assigns.game.id))}
  end

  def handle_event("move_down", %{"index" => index}, socket) do
    index = String.to_integer(index)
    lineup = move(socket.assigns.lineup, index, index + 1)

    {:ok, _slots} = Tracking.set_game_lineup(socket.assigns.game.id, Enum.map(lineup, & &1.id))
    {:noreply, assign(socket, :lineup, Tracking.list_lineup_players(socket.assigns.game.id))}
  end

  def handle_event("remove_player", %{"id" => id}, socket) do
    id = String.to_integer(id)
    lineup_ids = socket.assigns.lineup |> Enum.reject(&(&1.id == id)) |> Enum.map(& &1.id)
    {:ok, _slots} = Tracking.set_game_lineup(socket.assigns.game.id, lineup_ids)

    {:noreply,
     socket
     |> assign(:lineup, Tracking.list_lineup_players(socket.assigns.game.id))
     |> assign(:bench_players, Tracking.list_bench_players(socket.assigns.game.id))}
  end

  def handle_event("add_player", %{"id" => id}, socket) do
    id = String.to_integer(id)
    lineup_ids = Enum.map(socket.assigns.lineup, & &1.id)
    updated_ids = if id in lineup_ids, do: lineup_ids, else: lineup_ids ++ [id]
    {:ok, _slots} = Tracking.set_game_lineup(socket.assigns.game.id, updated_ids)

    {:noreply,
     socket
     |> assign(:lineup, Tracking.list_lineup_players(socket.assigns.game.id))
     |> assign(:bench_players, Tracking.list_bench_players(socket.assigns.game.id))}
  end

  defp move(list, from, to) when from < 0 or to < 0, do: list
  defp move(list, from, to) when from >= length(list) or to >= length(list), do: list

  defp move(list, from, to) do
    item = Enum.at(list, from)

    list
    |> List.delete_at(from)
    |> List.insert_at(to, item)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto w-full max-w-5xl space-y-5 pb-24 sm:pb-8">
        <.app_tabs current={:games} score_path={~p"/games/#{@game.id}/scoring"} />

        <section class="rounded-3xl border border-slate-200 bg-white p-5 shadow-sm sm:p-6">
          <div class="flex flex-wrap items-start justify-between gap-3">
            <div>
              <p class="text-xs uppercase tracking-[0.2em] text-slate-500">Lineup Setup</p>
              <h1 class="mt-1 text-2xl font-semibold text-slate-900">vs {@game.opponent_name}</h1>
              <p class="text-sm text-slate-600">
                {Calendar.strftime(@game.played_on, "%A, %b %d")} • {@game.location}
              </p>
            </div>

            <div class="flex gap-2">
              <.link navigate={~p"/games"} class="btn btn-soft">Back</.link>
              <.link navigate={~p"/games/#{@game.id}/scoring"} class="btn btn-primary">
                Start Scoring
              </.link>
            </div>
          </div>
        </section>

        <section class="grid gap-4 lg:grid-cols-[1.4fr_1fr]">
          <article class="rounded-3xl border border-slate-200 bg-white p-4 shadow-sm sm:p-6">
            <div class="flex items-center justify-between">
              <h2 class="text-sm font-semibold uppercase tracking-[0.2em] text-slate-500">
                Batting Order
              </h2>
              <span class="rounded-full bg-slate-100 px-2.5 py-1 text-xs font-semibold text-slate-700">
                {length(@lineup)} players
              </span>
            </div>

            <ol class="mt-4 space-y-2">
              <li
                :for={{player, index} <- Enum.with_index(@lineup)}
                id={"lineup-slot-#{player.id}"}
                class="rounded-2xl border border-slate-200 bg-slate-50 p-3"
              >
                <div class="flex items-center justify-between gap-3">
                  <div class="flex items-center gap-3">
                    <span class="inline-flex h-7 w-7 items-center justify-center rounded-full bg-blue-100 text-xs font-bold text-blue-900">
                      {index + 1}
                    </span>
                    <div>
                      <p class="font-semibold text-slate-900">
                        #{player.jersey_number} {player.name}
                      </p>
                      <p class="text-xs text-slate-500">Starter</p>
                    </div>
                  </div>

                  <div class="flex items-center gap-1">
                    <button
                      phx-click="move_up"
                      phx-value-index={index}
                      class="rounded-lg border border-slate-200 bg-white p-2 text-slate-600 hover:border-blue-300"
                      disabled={index == 0}
                    >
                      <.icon name="hero-chevron-up" class="size-4" />
                    </button>
                    <button
                      phx-click="move_down"
                      phx-value-index={index}
                      class="rounded-lg border border-slate-200 bg-white p-2 text-slate-600 hover:border-blue-300"
                      disabled={index == length(@lineup) - 1}
                    >
                      <.icon name="hero-chevron-down" class="size-4" />
                    </button>
                    <button
                      phx-click="remove_player"
                      phx-value-id={player.id}
                      class="rounded-lg border border-rose-200 bg-white p-2 text-rose-700 hover:bg-rose-50"
                    >
                      <.icon name="hero-minus-circle" class="size-4" />
                    </button>
                  </div>
                </div>
              </li>
            </ol>
          </article>

          <article class="rounded-3xl border border-slate-200 bg-white p-4 shadow-sm sm:p-6">
            <div class="flex items-center justify-between">
              <h2 class="text-sm font-semibold uppercase tracking-[0.2em] text-slate-500">
                Bench / Add Player
              </h2>
              <span class="rounded-full bg-slate-100 px-2.5 py-1 text-xs font-semibold text-slate-700">
                {length(@bench_players)}
              </span>
            </div>

            <div class="mt-4 space-y-2">
              <button
                :for={player <- @bench_players}
                id={"bench-player-#{player.id}"}
                phx-click="add_player"
                phx-value-id={player.id}
                class="flex w-full items-center justify-between rounded-xl border border-slate-200 bg-slate-50 px-3 py-2 text-left transition hover:border-blue-300 hover:bg-blue-50"
              >
                <span class="font-semibold text-slate-900">
                  #{player.jersey_number} {player.name}
                </span>
                <.icon name="hero-plus" class="size-4 text-slate-600" />
              </button>

              <p :if={@bench_players == []} class="rounded-xl bg-slate-50 p-3 text-sm text-slate-500">
                No additional active players available.
              </p>
            </div>
          </article>
        </section>
      </div>

      <.app_nav current={:games} score_path={~p"/games/#{@game.id}/scoring"} />
    </Layouts.app>
    """
  end
end
