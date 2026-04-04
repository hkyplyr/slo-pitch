defmodule SloPitch.Repo.Migrations.AddTeamHomeRunCountsToGames do
  use Ecto.Migration

  def change do
    alter table(:games) do
      add :home_home_runs, :integer, null: false, default: 0
      add :away_home_runs, :integer, null: false, default: 0
    end
  end
end
