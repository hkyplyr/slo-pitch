defmodule SloPitchWeb.RosterLive.Index do
  use SloPitchWeb, :live_view

  alias SloPitch.Tracking

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Roster")
     |> assign(:current_scope, nil)
     |> assign(:score_path, score_path())
     |> assign(:players, Tracking.list_players())
     |> assign(:form, to_form(%{"name" => "", "jersey_number" => ""}, as: :player))}
  end

  @impl true
  def handle_event("add_player", %{"player" => params}, socket) do
    name = String.trim(Map.get(params, "name", ""))
    jersey_number = String.trim(Map.get(params, "jersey_number", ""))

    if name == "" do
      {:noreply, put_flash(socket, :error, "Player name is required")}
    else
      case Tracking.create_player(%{
             name: name,
             jersey_number: parse_jersey(jersey_number),
             active: true
           }) do
        {:ok, _player} ->
          {:noreply,
           socket
           |> assign(:players, Tracking.list_players())
           |> assign(:form, to_form(%{"name" => "", "jersey_number" => ""}, as: :player))
           |> put_flash(:info, "Added #{name} to roster")}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Could not add player (name may already exist)")}
      end
    end
  end

  def handle_event("toggle_active", %{"id" => id}, socket) do
    id = String.to_integer(id)
    player = Enum.find(socket.assigns.players, &(&1.id == id))
    {:ok, _player} = Tracking.toggle_player_active(player)
    {:noreply, assign(socket, :players, Tracking.list_players())}
  end

  defp parse_jersey(""), do: nil

  defp parse_jersey(value) do
    case Integer.parse(value) do
      {number, _} -> number
      :error -> nil
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto w-full max-w-5xl space-y-5 pb-24 sm:pb-8">
        <.app_tabs current={:roster} score_path={@score_path} />

        <section class="rounded-3xl border border-slate-200 bg-white p-5 shadow-sm sm:p-6">
          <p class="text-xs uppercase tracking-[0.2em] text-slate-500">Roster</p>
          <h1 class="mt-1 text-2xl font-semibold text-slate-900">Players</h1>
          <p class="mt-1 text-sm text-slate-600">
            Manage active players available for lineup setup and in-game inserts.
          </p>

          <.form
            for={@form}
            id="player-form"
            class="mt-4 grid gap-3 sm:grid-cols-[1.6fr_1fr_auto]"
            phx-submit="add_player"
          >
            <.input
              field={@form[:name]}
              type="text"
              label="Player Name"
              placeholder="Alex Rivera"
              required
            />
            <.input
              field={@form[:jersey_number]}
              type="number"
              label="Jersey #"
              placeholder="12"
              min="0"
            />
            <button class="btn btn-primary mt-7 min-h-11">Add Player</button>
          </.form>
        </section>

        <section class="rounded-3xl border border-slate-200 bg-white p-4 shadow-sm sm:p-6">
          <div class="flex items-center justify-between">
            <h2 class="text-sm font-semibold uppercase tracking-[0.2em] text-slate-500">
              Current Roster
            </h2>
            <span class="rounded-full bg-slate-100 px-2.5 py-1 text-xs font-semibold text-slate-700">
              {length(@players)} total
            </span>
          </div>

          <div class="mt-4 grid gap-2 sm:grid-cols-2">
            <div
              :for={player <- @players}
              id={"roster-player-#{player.id}"}
              class={[
                "rounded-2xl border p-3",
                player.active && "border-emerald-200 bg-emerald-50",
                !player.active && "border-slate-200 bg-slate-50"
              ]}
            >
              <div class="flex items-center justify-between gap-3">
                <div>
                  <p class="font-semibold text-slate-900">
                    #{player.jersey_number || "--"} {player.name}
                  </p>
                  <p class="text-xs text-slate-500">
                    {if(player.active, do: "Active", else: "Inactive")}
                  </p>
                </div>

                <button
                  phx-click="toggle_active"
                  phx-value-id={player.id}
                  class={[
                    "rounded-xl px-3 py-2 text-xs font-semibold",
                    player.active && "bg-white text-rose-700 ring-1 ring-rose-200",
                    !player.active && "bg-white text-emerald-700 ring-1 ring-emerald-200"
                  ]}
                >
                  {if(player.active, do: "Set Inactive", else: "Set Active")}
                </button>
              </div>
            </div>
          </div>
        </section>
      </div>

      <.app_nav current={:roster} score_path={@score_path} />
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
