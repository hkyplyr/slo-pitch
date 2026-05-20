defmodule SloPitch.GameEngine.Bases do
  @moduledoc false

  @empty_bases %SloPitch.Tracking.GameState.Bases{first: nil, second: nil, third: nil}
  @default_runner_plan %{first: :auto, second: :auto, third: :auto, batter: :auto}

  @spec empty_bases() :: map()
  def empty_bases, do: @empty_bases

  @spec default_runner_plan() :: map()
  def default_runner_plan, do: @default_runner_plan

  @spec apply_result_to_bases(map(), atom(), String.t(), map()) ::
          {:ok, map(), list(), list()} | {:error, :base_conflict}
  def apply_result_to_bases(bases, result, batter_id, runner_plan \\ @default_runner_plan) do
    actors = [
      {:first, bases.first},
      {:second, bases.second},
      {:third, bases.third},
      {:batter, batter_id}
    ]

    case Enum.reduce_while(actors, {@empty_bases, [], []}, fn actor_and_player, acc ->
           reduce_runner(actor_and_player, acc, result, runner_plan)
         end) do
      {:error, :base_conflict} ->
        {:error, :base_conflict}

      {next_bases, runs, outs} ->
        {:ok, next_bases, runs, outs}
    end
  end

  defp reduce_runner({_actor, nil}, {next_bases, runs, outs}, _result, _runner_plan),
    do: {:cont, {next_bases, runs, outs}}

  defp reduce_runner({actor, player_id}, {next_bases, runs, outs}, result, runner_plan) do
    destination = planned_destination(actor, result, runner_plan)
    apply_runner_destination(next_bases, runs, outs, player_id, destination)
  end

  defp planned_destination(actor, result, runner_plan) do
    case Map.get(runner_plan, actor, :auto) do
      :auto -> auto_destination(actor, result)
      destination -> destination
    end
  end

  defp apply_runner_destination(next_bases, runs, outs, player_id, :out),
    do: {:cont, {next_bases, runs, [player_id | outs]}}

  defp apply_runner_destination(next_bases, runs, outs, player_id, :home),
    do: {:cont, {next_bases, [player_id | runs], outs}}

  defp apply_runner_destination(next_bases, runs, outs, player_id, destination)
       when destination in [:first, :second, :third] do
    if Map.get(next_bases, destination) do
      {:halt, {:error, :base_conflict}}
    else
      {:cont, {Map.put(next_bases, destination, player_id), runs, outs}}
    end
  end

  @type bases :: :first | :second | :third | :home

  @bases ~w(first second third home)a
  @bases_advanced %{
    out: 0,
    strikeout: 0,
    walk: 1,
    single: 1,
    double: 2,
    triple: 3,
    home_run: 4
  }

  @spec auto_destination(bases() | :batter, atom()) :: bases() | :out
  def auto_destination(:batter, action) when action in [:out, :strikeout], do: :out

  def auto_destination(position, action) when is_map_key(@bases_advanced, action) do
    bases_advanced = Map.fetch!(@bases_advanced, action)

    next_index =
      position
      |> current_index()
      |> next_index(bases_advanced)

    Enum.at(@bases, next_index)
  end

  defp current_index(position), do: Enum.find_index(@bases, &(&1 == position)) || -1

  defp next_index(current_index, bases_advanced),
    do: min(current_index + bases_advanced, length(@bases) - 1)

  def default_runner_plan_for_result(result) do
    %{
      first: auto_destination(:first, result),
      second: auto_destination(:second, result),
      third: auto_destination(:third, result),
      batter: auto_destination(:batter, result)
    }
  end
end
