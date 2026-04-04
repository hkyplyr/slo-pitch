defmodule SloPitchWeb.StatsLive.Index do
  use SloPitchWeb, :live_view

  alias SloPitch.Tracking

  @impl true
  def mount(_params, _session, socket) do
    stats = Tracking.player_stats(:season)
    score_path = score_path()

    {:ok,
     socket
     |> assign(:page_title, "Stats")
     |> assign(:current_scope, nil)
     |> assign(:score_path, score_path)
     |> assign(:window, :season)
     |> assign(:sort_by, :avg)
     |> assign(:stats, sort_stats(stats, :avg))}
  end

  @impl true
  def handle_event("set_window", %{"value" => value}, socket) do
    window = if value == "last5", do: :last5, else: :season

    stats = Tracking.player_stats(window)

    {:noreply,
     socket
     |> assign(:window, window)
     |> assign(:stats, sort_stats(stats, socket.assigns.sort_by))}
  end

  def handle_event("sort", %{"field" => field}, socket) do
    sort_by = String.to_existing_atom(field)

    {:noreply,
     socket
     |> assign(:sort_by, sort_by)
     |> assign(:stats, sort_stats(socket.assigns.stats, sort_by))}
  end

  defp sort_stats(stats, :avg) do
    Enum.sort_by(stats, &avg(&1), :desc)
  end

  defp sort_stats(stats, :h), do: Enum.sort_by(stats, & &1.h, :desc)
  defp sort_stats(stats, :rbi), do: Enum.sort_by(stats, & &1.rbi, :desc)
  defp sort_stats(stats, :pa), do: Enum.sort_by(stats, & &1.pa, :desc)
  defp sort_stats(stats, _), do: stats

  defp avg(stat) do
    if stat.ab == 0 do
      0.0
    else
      stat.h / stat.ab
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto w-full max-w-6xl space-y-5 pb-24 sm:pb-8">
        <.app_tabs current={:stats} score_path={@score_path} />

        <section class="rounded-3xl border border-slate-200 bg-white p-5 shadow-sm sm:p-6">
          <div class="flex flex-wrap items-start justify-between gap-3">
            <div>
              <p class="text-xs uppercase tracking-[0.2em] text-slate-500">Offensive Stats</p>
              <h1 class="mt-1 text-2xl font-semibold text-slate-900">Player Performance</h1>
            </div>

            <div class="rounded-2xl bg-slate-100 p-1">
              <button
                phx-click="set_window"
                phx-value-value="season"
                class={[
                  "rounded-xl px-3 py-2 text-sm font-semibold",
                  @window == :season && "bg-white text-blue-900 shadow-sm",
                  @window != :season && "text-slate-600"
                ]}
              >
                Season
              </button>
              <button
                phx-click="set_window"
                phx-value-value="last5"
                class={[
                  "rounded-xl px-3 py-2 text-sm font-semibold",
                  @window == :last5 && "bg-white text-blue-900 shadow-sm",
                  @window != :last5 && "text-slate-600"
                ]}
              >
                Last 5
              </button>
            </div>
          </div>

          <div class="mt-4 flex flex-wrap gap-2">
            <button phx-click="sort" phx-value-field="avg" class="btn btn-soft btn-sm">
              Sort AVG
            </button>
            <button phx-click="sort" phx-value-field="h" class="btn btn-soft btn-sm">
              Sort Hits
            </button>
            <button phx-click="sort" phx-value-field="rbi" class="btn btn-soft btn-sm">
              Sort RBI
            </button>
            <button phx-click="sort" phx-value-field="pa" class="btn btn-soft btn-sm">Sort PA</button>
          </div>
        </section>

        <section class="rounded-3xl border border-slate-200 bg-white p-4 shadow-sm sm:p-6">
          <div class="overflow-x-auto rounded-2xl border border-slate-200">
            <table class="w-full text-sm">
              <thead class="bg-slate-100 text-left text-xs uppercase tracking-[0.13em] text-slate-500">
                <tr>
                  <th class="px-3 py-2">Player</th>
                  <th class="px-3 py-2">PA</th>
                  <th class="px-3 py-2">AB</th>
                  <th class="px-3 py-2">H</th>
                  <th class="px-3 py-2">1B</th>
                  <th class="px-3 py-2">2B</th>
                  <th class="px-3 py-2">3B</th>
                  <th class="px-3 py-2">HR</th>
                  <th class="px-3 py-2">BB</th>
                  <th class="px-3 py-2">K</th>
                  <th class="px-3 py-2">OUT</th>
                  <th class="px-3 py-2">R</th>
                  <th class="px-3 py-2">RBI</th>
                  <th class="px-3 py-2">AVG</th>
                </tr>
              </thead>
              <tbody>
                <tr
                  :for={stat <- @stats}
                  id={"stat-row-#{String.replace(stat.player_name, " ", "-")}"}
                  class="border-t border-slate-200 bg-white"
                >
                  <td class="px-3 py-2 font-medium text-slate-900">{stat.player_name}</td>
                  <td class="px-3 py-2 text-slate-700">{stat.pa}</td>
                  <td class="px-3 py-2 text-slate-700">{stat.ab}</td>
                  <td class="px-3 py-2 font-semibold text-slate-900">{stat.h}</td>
                  <td class="px-3 py-2 text-slate-700">{stat.single}</td>
                  <td class="px-3 py-2 text-slate-700">{stat.double}</td>
                  <td class="px-3 py-2 text-slate-700">{stat.triple}</td>
                  <td class="px-3 py-2 text-slate-700">{stat.home_run}</td>
                  <td class="px-3 py-2 text-slate-700">{stat.bb}</td>
                  <td class="px-3 py-2 text-slate-700">{stat.k}</td>
                  <td class="px-3 py-2 text-slate-700">{stat.out}</td>
                  <td class="px-3 py-2 text-slate-700">{stat.r}</td>
                  <td class="px-3 py-2 text-slate-700">{stat.rbi}</td>
                  <td class="px-3 py-2 font-semibold text-blue-900">{Float.round(avg(stat), 3)}</td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>
      </div>

      <.app_nav current={:stats} score_path={@score_path} />
    </Layouts.app>
    """
  end

  defp score_path do
    case Tracking.list_recent_games(1) do
      [game] -> "/games/#{game.id}/scoring"
      [] -> "/games"
    end
  end
end
