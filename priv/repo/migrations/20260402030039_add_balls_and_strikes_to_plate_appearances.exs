defmodule SloPitch.Repo.Migrations.AddBallsAndStrikesToPlateAppearances do
  use Ecto.Migration

  def change do
    alter table(:plate_appearances) do
      add :balls, :integer, null: false, default: 0
      add :strikes, :integer, null: false, default: 0
    end
  end
end
