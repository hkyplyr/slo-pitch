defmodule SloPitchWeb.GamesLive.Index do
  use SloPitchWeb, :live_view

  alias SloPitch.Tracking

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Games")
     |> assign(:current_scope, nil)
     |> assign(:game_form, new_game_form())
     |> assign_game_lists()}
  end

  @impl true
  def handle_event("create_game", %{"game" => params}, socket) do
    attrs = %{
      opponent_name: String.trim(Map.get(params, "opponent_name", "")),
      played_on: Map.get(params, "played_on", ""),
      location: blank_to_nil(Map.get(params, "location", "")),
      home_or_away: Map.get(params, "home_or_away", "away"),
      status: "scheduled"
    }

    case Tracking.create_game(attrs) do
      {:ok, game} ->
        {:noreply,
         socket
         |> put_flash(:info, "Created game vs #{game.opponent_name}")
         |> assign(:game_form, new_game_form())
         |> assign_game_lists()}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not create game")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto w-full max-w-5xl space-y-6 pb-24 sm:pb-8">
        <.app_tabs current={:games} score_path={@score_path} />

        <section class="rounded-3xl bg-gradient-to-br from-blue-700 via-blue-800 to-slate-900 p-5 text-white shadow-xl shadow-blue-950/20 sm:p-7">
          <p class="text-xs uppercase tracking-[0.2em] text-blue-100">Slo-Pitch Manager</p>
          <h1 class="mt-1 text-2xl font-semibold sm:text-3xl">Game Center</h1>
          <p class="mt-2 max-w-xl text-sm text-blue-100 sm:text-base">
            Manage game day flow from lineup setup through live scoring and post-game recap.
          </p>

          <.form
            for={@game_form}
            id="new-game-form"
            class="mt-5 grid gap-3 sm:grid-cols-3"
            phx-submit="create_game"
          >
            <.input
              field={@game_form[:opponent_name]}
              type="text"
              label="Opponent"
              placeholder="Prairie Heat"
              required
            />
            <.input field={@game_form[:played_on]} type="date" label="Date" required />
            <.input
              field={@game_form[:location]}
              type="text"
              label="Location"
              placeholder="Rotary Park"
            />
            <.input
              field={@game_form[:home_or_away]}
              type="select"
              label="Our Team"
              options={[{"Away (bat first)", "away"}, {"Home (bat second)", "home"}]}
            />
            <button class="btn btn-primary sm:col-span-3">Create Scheduled Game</button>
          </.form>
        </section>

        <section class="grid gap-4 lg:grid-cols-2">
          <article class="rounded-3xl border border-slate-200 bg-white p-4 shadow-sm sm:p-6">
            <div class="flex items-center justify-between">
              <h2 class="text-sm font-semibold uppercase tracking-[0.2em] text-slate-500">
                In Progress
              </h2>
              <span class="rounded-full bg-blue-100 px-2.5 py-1 text-xs font-semibold text-blue-900">
                {length(@in_progress)}
              </span>
            </div>
            <div class="mt-3 space-y-3">
              <div
                :for={game <- @in_progress}
                id={"in-progress-game-#{game.id}"}
                class="rounded-2xl border border-blue-100 bg-blue-50 p-3"
              >
                <div class="flex items-start justify-between gap-3">
                  <div>
                    <p class="text-sm font-semibold text-slate-900">vs {game.opponent_name}</p>
                    <p class="text-xs text-slate-600">
                      {game.location || "TBD"} • {Calendar.strftime(game.played_on, "%b %d")}
                    </p>
                  </div>
                  <p class="text-lg font-bold text-blue-900">{game.our_score}-{game.opp_score}</p>
                </div>
                <div class="mt-3 flex flex-wrap gap-2">
                  <.link navigate={~p"/games/#{game.id}/scoring"} class="btn btn-sm btn-primary">
                    Resume
                  </.link>
                  <.link navigate={~p"/games/#{game.id}"} class="btn btn-sm btn-soft">Summary</.link>
                </div>
              </div>
              <p :if={@in_progress == []} class="rounded-xl bg-slate-50 p-3 text-sm text-slate-500">
                No games in progress.
              </p>
            </div>
          </article>

          <article class="rounded-3xl border border-slate-200 bg-white p-4 shadow-sm sm:p-6">
            <div class="flex items-center justify-between">
              <h2 class="text-sm font-semibold uppercase tracking-[0.2em] text-slate-500">
                Scheduled
              </h2>
              <span class="rounded-full bg-slate-100 px-2.5 py-1 text-xs font-semibold text-slate-700">
                {length(@scheduled)}
              </span>
            </div>
            <div class="mt-3 space-y-3">
              <div
                :for={game <- @scheduled}
                id={"scheduled-game-#{game.id}"}
                class="rounded-2xl border border-slate-200 bg-slate-50 p-3"
              >
                <p class="text-sm font-semibold text-slate-900">vs {game.opponent_name}</p>
                <p class="text-xs text-slate-600">
                  {game.location || "TBD"} • {Calendar.strftime(game.played_on, "%A, %b %d")}
                </p>
                <div class="mt-3 flex flex-wrap gap-2">
                  <.link navigate={~p"/games/#{game.id}/setup"} class="btn btn-sm btn-primary">
                    Build Lineup
                  </.link>
                  <.link navigate={~p"/games/#{game.id}"} class="btn btn-sm btn-soft">Preview</.link>
                </div>
              </div>
              <p :if={@scheduled == []} class="rounded-xl bg-slate-50 p-3 text-sm text-slate-500">
                No scheduled games yet.
              </p>
            </div>
          </article>
        </section>

        <section class="rounded-3xl border border-slate-200 bg-white p-4 shadow-sm sm:p-6">
          <div class="flex items-center justify-between">
            <h2 class="text-sm font-semibold uppercase tracking-[0.2em] text-slate-500">
              Recent Final Scores
            </h2>
            <.link
              navigate={~p"/stats"}
              class="text-sm font-semibold text-blue-700 hover:text-blue-900"
            >
              View Season Stats
            </.link>
          </div>

          <div class="mt-4 overflow-hidden rounded-2xl border border-slate-200">
            <table class="w-full text-sm">
              <thead class="bg-slate-100 text-left text-xs uppercase tracking-[0.14em] text-slate-500">
                <tr>
                  <th class="px-3 py-2">Date</th>
                  <th class="px-3 py-2">Opponent</th>
                  <th class="px-3 py-2">Score</th>
                  <th class="px-3 py-2">Result</th>
                  <th class="px-3 py-2"></th>
                </tr>
              </thead>
              <tbody>
                <tr
                  :for={game <- @recent}
                  id={"recent-game-#{game.id}"}
                  class="border-t border-slate-200 bg-white"
                >
                  <td class="px-3 py-2 text-slate-700">
                    {Calendar.strftime(game.played_on, "%b %d")}
                  </td>
                  <td class="px-3 py-2 font-medium text-slate-900">{game.opponent_name}</td>
                  <td class="px-3 py-2 font-semibold text-slate-900">
                    {game.our_score}-{game.opp_score}
                  </td>
                  <td class="px-3 py-2">
                    <span class={[
                      "rounded-full px-2 py-1 text-xs font-semibold",
                      game.our_score > game.opp_score && "bg-emerald-100 text-emerald-900",
                      game.our_score <= game.opp_score && "bg-rose-100 text-rose-900"
                    ]}>
                      {if(game.our_score > game.opp_score, do: "W", else: "L")}
                    </span>
                  </td>
                  <td class="px-3 py-2 text-right">
                    <.link
                      navigate={~p"/games/#{game.id}"}
                      class="text-xs font-semibold text-blue-700 hover:text-blue-900"
                    >
                      Details
                    </.link>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>
      </div>

      <.app_nav current={:games} score_path={@score_path} />
    </Layouts.app>
    """
  end

  defp assign_game_lists(socket) do
    games = Tracking.list_games()

    in_progress = Enum.filter(games, &(status_atom(&1.status) == :in_progress))
    scheduled = Enum.filter(games, &(status_atom(&1.status) == :scheduled))
    recent = Enum.filter(games, &(status_atom(&1.status) == :final))

    score_path =
      case in_progress ++ scheduled ++ recent do
        [game | _] -> "/games/#{game.id}/scoring"
        [] -> "/games"
      end

    socket
    |> assign(:in_progress, in_progress)
    |> assign(:scheduled, scheduled)
    |> assign(:recent, recent)
    |> assign(:score_path, score_path)
  end

  defp new_game_form do
    to_form(
      %{
        "opponent_name" => "",
        "played_on" => Date.to_iso8601(Date.utc_today()),
        "location" => "",
        "home_or_away" => "away"
      },
      as: :game
    )
  end

  defp blank_to_nil(value) do
    case String.trim(value) do
      "" -> nil
      v -> v
    end
  end

  defp status_atom(status) when is_atom(status), do: status

  defp status_atom(status) when is_binary(status) do
    case status do
      "scheduled" -> :scheduled
      "in_progress" -> :in_progress
      "final" -> :final
      _ -> :scheduled
    end
  end
end
