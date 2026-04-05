defmodule SloPitch.GameEngine.Bases do
  @empty_bases %{first: nil, second: nil, third: nil}
  @default_runner_plan %{first: :auto, second: :auto, third: :auto, batter: :auto}

  def apply_result_to_bases(bases, result, batter_id) do
    apply_result_to_bases(bases, result, batter_id, @default_runner_plan)
  end

  def apply_result_to_bases(bases, result, batter_id, runner_plan) do
    actors = [
      {:first, bases.first},
      {:second, bases.second},
      {:third, bases.third},
      {:batter, batter_id}
    ]

    case Enum.reduce_while(actors, {@empty_bases, 0}, fn actor_and_player, acc ->
           reduce_runner(actor_and_player, acc, result, runner_plan)
         end) do
      {:error, :base_conflict} ->
        {:error, :base_conflict}

      {next_bases, runs} ->
        rbis = if result == "strikeout", do: 0, else: runs
        {:ok, next_bases, runs, rbis}
    end
  end

  defp reduce_runner({_actor, nil}, {next_bases, runs}, _result, _runner_plan),
    do: {:cont, {next_bases, runs}}

  defp reduce_runner({actor, player_id}, {next_bases, runs}, result, runner_plan) do
    destination = planned_destination(actor, result, runner_plan)
    apply_runner_destination(next_bases, runs, player_id, destination)
  end

  defp planned_destination(actor, result, runner_plan) do
    case Map.get(runner_plan, actor, :auto) do
      :auto -> auto_destination(actor, result)
      destination -> destination
    end
  end

  defp apply_runner_destination(next_bases, runs, _player_id, :out),
    do: {:cont, {next_bases, runs}}

  defp apply_runner_destination(next_bases, runs, _player_id, :home),
    do: {:cont, {next_bases, runs + 1}}

  defp apply_runner_destination(next_bases, runs, player_id, destination)
       when destination in [:first, :second, :third] do
    if Map.get(next_bases, destination) do
      {:halt, {:error, :base_conflict}}
    else
      {:cont, {Map.put(next_bases, destination, player_id), runs}}
    end
  end

  @type bases :: :first | :second | :third | :home

  @bases ~w(first second third home)a
  @bases_advanced %{
    "out" => 0,
    "strikeout" => 0,
    "walk" => 1,
    "single" => 1,
    "double" => 2,
    "triple" => 3,
    "home_run" => 4
  }

  @spec auto_destination(bases() | :batter, String.t()) :: bases() | :out
  def auto_destination(:batter, action) when action in ["out", "strikeout"], do: :out

  def auto_destination(position, action) when is_map_key(@bases_advanced, action) do
    bases_advanced = Map.fetch!(@bases_advanced, action)
    current_index = current_index(position)

    Enum.at(@bases, next_index(current_index, bases_advanced))
  end

  defp current_index(:batter), do: -1
  defp current_index(position), do: Enum.find_index(@bases, &(&1 == position))

  defp next_index(current_index, bases_advanced),
    do: min(current_index + bases_advanced, length(@bases) - 1)
end
