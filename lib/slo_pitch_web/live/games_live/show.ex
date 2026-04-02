defmodule SloPitchWeb.GamesLive.Show do
  use SloPitchWeb, :live_view

  alias SloPitch.Tracking

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    game_id = String.to_integer(id)
    game = Tracking.get_game!(game_id)

    {:ok,
     socket
     |> assign(:page_title, "Game Summary")
     |> assign(:current_scope, nil)
     |> assign(:game, game)
     |> assign(:innings, Tracking.list_innings(game_id))
     |> assign(:our_runs_by_inning, our_runs_by_inning(game_id))
     |> assign(:batting_lines, game_batting_lines(game_id))}
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
              <h1 class="mt-1 text-2xl font-semibold sm:text-3xl">vs {@game.opponent_name}</h1>
              <p class="text-sm text-blue-100">
                {Calendar.strftime(@game.played_on, "%A, %b %d")} • {@game.location}
              </p>
            </div>
            <div class="rounded-2xl bg-white/15 px-4 py-3 text-right backdrop-blur">
              <p class="text-xs uppercase tracking-[0.2em] text-blue-100">Final</p>
              <p class="text-3xl font-bold">{@game.our_score} - {@game.opp_score}</p>
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
                    <th :for={inning <- @innings} class="px-3 py-2">{inning.inning_number}</th>
                    <th class="px-3 py-2">R</th>
                  </tr>
                </thead>
                <tbody>
                  <tr id="line-score-away" class="border-t border-slate-200 bg-white">
                    <td class="px-3 py-2 font-medium text-slate-700">{@game.opponent_name}</td>
                    <td :for={inning <- @innings} class="px-3 py-2 font-semibold text-slate-900">
                      {inning.opp_runs}
                    </td>
                    <td class="px-3 py-2 font-bold text-slate-900">{@game.opp_score}</td>
                  </tr>
                  <tr id="line-score-home" class="border-t border-slate-200 bg-slate-50">
                    <td class="px-3 py-2 font-medium text-slate-700">Slo-Pitch</td>
                    <td :for={inning <- @innings} class="px-3 py-2 font-semibold text-blue-900">
                      {Map.get(@our_runs_by_inning, inning.inning_number, 0)}
                    </td>
                    <td class="px-3 py-2 font-bold text-blue-900">{@game.our_score}</td>
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
                  <th class="px-3 py-2">PA</th>
                  <th class="px-3 py-2">AB</th>
                  <th class="px-3 py-2">H</th>
                  <th class="px-3 py-2">BB</th>
                  <th class="px-3 py-2">R</th>
                  <th class="px-3 py-2">RBI</th>
                </tr>
              </thead>
              <tbody>
                <tr
                  :for={line <- @batting_lines}
                  id={"batting-line-#{String.replace(line.player_name, " ", "-")}"}
                  class="border-t border-slate-200 bg-white"
                >
                  <td class="px-3 py-2 font-medium text-slate-900">{line.player_name}</td>
                  <td class="px-3 py-2 text-slate-700">{line.pa}</td>
                  <td class="px-3 py-2 text-slate-700">{line.ab}</td>
                  <td class="px-3 py-2 font-semibold text-slate-900">{line.h}</td>
                  <td class="px-3 py-2 text-slate-700">{line.bb}</td>
                  <td class="px-3 py-2 text-slate-700">{line.r}</td>
                  <td class="px-3 py-2 font-semibold text-slate-900">{line.rbi}</td>
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

  defp game_batting_lines(game_id) do
    appearances = Tracking.list_plate_appearances(game_id)
    run_totals = Tracking.run_totals_by_player(appearances)

    appearances
    |> Enum.group_by(& &1.player)
    |> Enum.map(fn {player, appearances} ->
      pa = length(appearances)
      walks = Enum.count(appearances, &(&1.result == "walk"))
      hits = Enum.count(appearances, &(&1.result in ["single", "double", "triple", "home_run"]))
      ab = pa - walks
      runs = Map.get(run_totals, player.id, 0)
      rbi = Enum.reduce(appearances, 0, &(&1.rbis + &2))

      %{player_name: player.name, pa: pa, ab: ab, h: hits, bb: walks, r: runs, rbi: rbi}
    end)
    |> Enum.sort_by(& &1.player_name)
  end

  defp our_runs_by_inning(game_id) do
    Tracking.list_plate_appearances(game_id)
    |> Enum.group_by(& &1.inning)
    |> Map.new(fn {inning, appearances} ->
      runs = Enum.reduce(appearances, 0, &(&1.runs_scored + &2))
      {inning, runs}
    end)
  end
end
