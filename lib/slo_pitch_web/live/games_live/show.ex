defmodule SloPitchWeb.GamesLive.Show do
  use SloPitchWeb, :live_view

  alias SloPitch.Tracking
  alias SloPitch.Tracking.Games
  alias SloPitch.Tracking.GameState
  alias SloPitch.Tracking.GameState.PlayerStatistics

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    game_id = String.to_integer(id)
    game = Tracking.get_game!(game_id)
    game_state = Games.rebuild_game_state(game)

    {:ok,
     socket
     |> assign(:page_title, "Game Summary")
     |> assign(:current_scope, nil)
     |> assign(:game, game)
     |> assign(:game_state, game_state)
     |> assign(:innings, [])
     |> assign(:our_runs_by_inning, [])
     |> assign(:statistics, prepare_statistics(game_state))}
  end

  defp prepare_statistics(%GameState{statistics: statistics, lineup: lineup}) do
    lineup
    |> Enum.reduce([], fn player, acc ->
      stats =
        statistics
        |> Map.get(player.id)
        |> PlayerStatistics.normalize()

      [%{player: player, stats: stats} | acc]
    end)
    |> Enum.reverse()
  end

  defp format_percentage(value) do
    value
    |> :erlang.float_to_binary([{:decimals, 3}])
    |> String.replace(~r/^0(?=\.)/, "")
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto w-full max-w-5xl space-y-5 pb-24 sm:pb-8">
        <.app_tabs current={:games} score_path={~p"/games/#{@game.id}/scoring"} />

        <section class="rounded-3xl bg-gradient-to-r from-slate-900 via-blue-900 to-blue-700 p-5 text-white shadow-xl shadow-blue-950/20 sm:p-7">
          <div class="flex flex-wrap items-end justify-between gap-4">
            <div>
              <p class="text-xs uppercase tracking-[0.2em] text-blue-100">Game Summary</p>
              <h1 class="mt-1 text-2xl font-semibold sm:text-3xl">
                {if @game.alignment == :away, do: "@", else: "vs."} {@game.opponent_name}
              </h1>
              <p class="text-sm text-blue-100">
                {Calendar.strftime(@game.played_on, "%A, %b %d")} • {@game.location}
              </p>
            </div>
            <div class="rounded-2xl bg-white/15 px-4 py-3 text-right backdrop-blur">
              <p class="text-xs uppercase tracking-[0.2em] text-blue-100">Final</p>
              <p class="text-3xl font-bold">Score</p>
            </div>
          </div>

          <div class="mt-4 flex flex-wrap gap-2">
            <.link navigate={~p"/games"} class="btn btn-soft btn-sm">Back to Games</.link>
            <.link navigate={~p"/games/#{@game.id}/setup"} class="btn btn-soft btn-sm">
              Edit Lineup
            </.link>
            <.link navigate={~p"/games/#{@game.id}/scoring"} class="btn btn-primary btn-sm">
              Edit Scoring
            </.link>
          </div>
        </section>

        <section>
          <article class="rounded-3xl border border-slate-200 bg-white p-4 shadow-sm sm:p-6">
            <h2 class="text-sm font-semibold uppercase tracking-[0.2em] text-slate-500">
              Line Score
            </h2>

            <div class="mt-4 overflow-hidden rounded-2xl border border-slate-200">
              <table class="w-full text-sm">
                <thead class="bg-slate-100 text-left text-xs uppercase tracking-[0.14em] text-slate-500">
                  <tr>
                    <th class="px-3 py-2">Team</th>
                    <th :for={inning <- @game_state.innings} class="px-3 py-2">{inning.number}</th>
                    <th class="px-3 py-2">R</th>
                  </tr>
                </thead>
                <tbody>
                  <tr id="line-score-away" class="border-t border-slate-200 bg-white">
                    <td class="px-3 py-2 font-medium text-slate-700">
                      {if @game_state.alignment == :away, do: "Slamingoes", else: @game.opponent_name}
                    </td>
                    <td
                      :for={inning <- @game_state.innings}
                      class="px-3 py-2 font-semibold text-slate-900"
                    >
                      {inning.score.away}
                    </td>
                    <td class="px-3 py-2 font-bold text-slate-900">
                      {GameState.game_score(@game_state).away}
                    </td>
                  </tr>
                  <tr id="line-score-home" class="border-t border-slate-200 bg-slate-50">
                    <td class="px-3 py-2 font-medium text-slate-700">
                      {if @game_state.alignment == :home, do: "Slamingoes", else: @game.opponent_name}
                    </td>
                    <td
                      :for={inning <- @game_state.innings}
                      class="px-3 py-2 font-semibold text-blue-900"
                    >
                      {inning.score.home}
                    </td>
                    <td class="px-3 py-2 font-bold text-blue-900">
                      {GameState.game_score(@game_state).home}
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </article>
        </section>

        <section class="rounded-3xl border border-slate-200 bg-white p-4 shadow-sm sm:p-6">
          <h2 class="text-sm font-semibold uppercase tracking-[0.2em] text-slate-500">
            Batting Lines
          </h2>

          <div class="mt-4 overflow-hidden rounded-2xl border border-slate-200">
            <table class="w-full text-sm">
              <thead class="bg-slate-100 text-left text-xs uppercase tracking-[0.14em] text-slate-500">
                <tr>
                  <th class="px-3 py-2">Player</th>
                  <th class="px-3 py-2">AB</th>
                  <th class="px-3 py-2">R</th>
                  <th class="px-3 py-2">H</th>
                  <th class="px-3 py-2">2B</th>
                  <th class="px-3 py-2">3B</th>
                  <th class="px-3 py-2">HR</th>
                  <th class="px-3 py-2">RBI</th>
                  <th class="px-3 py-2">BB</th>
                  <th class="px-3 py-2">SO</th>
                  <th class="px-3 py-2">AVG</th>
                  <th class="px-3 py-2">SLG</th>
                </tr>
              </thead>
              <tbody>
                <tr
                  :for={{row, idx} <- Enum.with_index(@statistics, 1)}
                  id={"batting-line-#{row.player.id}"}
                  class="border-t border-slate-200 bg-white"
                >
                  <td class="px-3 py-2 font-medium text-slate-900">{idx}. {row.player.name}</td>
                  <td class="px-3 py-2 text-slate-700">{row.stats.at_bats}</td>
                  <td class="px-3 py-2 text-slate-700">{row.stats.runs}</td>
                  <td class="px-3 py-2 text-slate-700">{row.stats.hits}</td>
                  <td class="px-3 py-2 text-slate-700">{row.stats.doubles}</td>
                  <td class="px-3 py-2 text-slate-700">{row.stats.triples}</td>
                  <td class="px-3 py-2 text-slate-700">{row.stats.home_runs}</td>
                  <td class="px-3 py-2 text-slate-700">{row.stats.rbis}</td>
                  <td class="px-3 py-2 text-slate-700">{row.stats.walks}</td>
                  <td class="px-3 py-2 text-slate-700">{row.stats.strikeouts}</td>
                  <td class="px-3 py-2 text-slate-700">{format_percentage(row.stats.average)}</td>
                  <td class="px-3 py-2 text-slate-700">{format_percentage(row.stats.slugging)}</td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>
      </div>

      <.app_nav current={:games} score_path={~p"/games/#{@game.id}/scoring"} />
    </Layouts.app>
    """
  end
end
