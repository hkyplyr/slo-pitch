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
      add :our_score, :integer, null: false, default: 0
      add :opp_score, :integer, null: false, default: 0

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

    create table(:game_innings) do
      add :inning_number, :integer, null: false
      add :our_runs, :integer, null: false, default: 0
      add :opp_runs, :integer, null: false, default: 0
      add :game_id, references(:games, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:game_innings, [:game_id, :inning_number])

    create table(:plate_appearances) do
      add :sequence_number, :integer, null: false
      add :inning, :integer, null: false
      add :result, :string, null: false
      add :runs_scored, :integer, null: false, default: 0
      add :rbis, :integer, null: false, default: 0
      add :skip, :boolean, null: false, default: false
      add :inserted_batter, :boolean, null: false, default: false
      add :game_id, references(:games, on_delete: :delete_all), null: false
      add :player_id, references(:players, on_delete: :restrict), null: false
      add :lineup_slot_id, references(:game_lineup_slots, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:plate_appearances, [:game_id])
    create index(:plate_appearances, [:player_id])
    create unique_index(:plate_appearances, [:game_id, :sequence_number])
  end
end
