defmodule SloPitch.Repo.Migrations.CreateTrackingTables do
  use Ecto.Migration

  def change do
    create table(:players) do
      add :name, :string, null: false
      add :jersey_number, :integer
      add :active, :boolean, null: false, default: true

      timestamps(type: :utc_datetime)
    end

    create index(:players, [:active])
    create unique_index(:players, [:name])

    create table(:games) do
      add :opponent_name, :string, null: false
      add :played_on, :date, null: false
      add :location, :string
      add :status, :string, null: false, default: "scheduled"
      add :alignment, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:games, [:played_on])
    create index(:games, [:status])

    create table(:game_lineup_slots) do
      add :batting_order, :integer, null: false
      add :starter, :boolean, null: false, default: true
      add :game_id, references(:games, on_delete: :delete_all), null: false
      add :player_id, references(:players, on_delete: :restrict), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:game_lineup_slots, [:game_id])
    create unique_index(:game_lineup_slots, [:game_id, :batting_order])
    create unique_index(:game_lineup_slots, [:game_id, :player_id])
  end
end
