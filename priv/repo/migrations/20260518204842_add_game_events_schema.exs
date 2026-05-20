defmodule SloPitch.Repo.Migrations.AddGameEventsSchema do
  use Ecto.Migration

  def change do
    create table(:game_events) do
      add :type, :string, null: false
      add :result, :string, null: false
      add :runner_plan, :map
      add :game_id, references(:games, on_delete: :delete_all)
      add :player_id, references(:players, on_delete: :delete_all)

      timestamps()
    end
  end
end
