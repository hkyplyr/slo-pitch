defmodule SloPitchWeb.AppNavComponents do
  @moduledoc """
  Shared navigation UI components for app pages.
  """

  use Phoenix.Component

  import SloPitchWeb.CoreComponents

  attr :current, :atom, required: true
  attr :score_path, :string, default: "/games"

  def app_tabs(assigns) do
    ~H"""
    <nav class="hidden sm:block">
      <ul class="grid grid-cols-4 gap-2 rounded-2xl border border-slate-200 bg-white p-2 shadow-sm">
        <li>
          <.link navigate="/games" class={tab_class(@current == :games)}>
            <.icon name="hero-calendar-days" class="size-4" /> Games
          </.link>
        </li>
        <li>
          <.link navigate="/roster" class={tab_class(@current == :roster)}>
            <.icon name="hero-users" class="size-4" /> Roster
          </.link>
        </li>
        <li>
          <.link navigate="/stats" class={tab_class(@current == :stats)}>
            <.icon name="hero-chart-bar" class="size-4" /> Stats
          </.link>
        </li>
        <li>
          <.link navigate={@score_path} class={tab_class(@current == :scoring)}>
            <.icon name="hero-bolt" class="size-4" /> Score
          </.link>
        </li>
      </ul>
    </nav>
    """
  end

  attr :current, :atom, required: true
  attr :score_path, :string, default: "/games"

  def app_nav(assigns) do
    ~H"""
    <nav class="fixed inset-x-0 bottom-0 z-40 border-t border-slate-200 bg-white/95 px-4 py-2 backdrop-blur sm:hidden">
      <ul class="mx-auto grid max-w-xl grid-cols-4 gap-2">
        <li>
          <.link navigate="/games" class={nav_class(@current == :games)}>
            <.icon name="hero-calendar-days" class="size-4" /> Games
          </.link>
        </li>
        <li>
          <.link navigate="/roster" class={nav_class(@current == :roster)}>
            <.icon name="hero-users" class="size-4" /> Roster
          </.link>
        </li>
        <li>
          <.link navigate="/stats" class={nav_class(@current == :stats)}>
            <.icon name="hero-chart-bar" class="size-4" /> Stats
          </.link>
        </li>
        <li>
          <.link navigate={@score_path} class={nav_class(@current == :scoring)}>
            <.icon name="hero-bolt" class="size-4" /> Score
          </.link>
        </li>
      </ul>
    </nav>
    """
  end

  defp nav_class(true) do
    "flex min-h-12 flex-col items-center justify-center gap-1 rounded-xl bg-blue-100 px-2 py-1 text-xs font-semibold text-blue-900"
  end

  defp nav_class(false) do
    "flex min-h-12 flex-col items-center justify-center gap-1 rounded-xl px-2 py-1 text-xs font-semibold text-slate-500 transition hover:bg-slate-100 hover:text-slate-900"
  end

  defp tab_class(true) do
    "inline-flex min-h-12 w-full items-center justify-center gap-2 rounded-xl bg-blue-100 px-3 py-2 text-sm font-semibold text-blue-900"
  end

  defp tab_class(false) do
    "inline-flex min-h-12 w-full items-center justify-center gap-2 rounded-xl px-3 py-2 text-sm font-semibold text-slate-600 transition hover:bg-slate-100 hover:text-slate-900"
  end
end
