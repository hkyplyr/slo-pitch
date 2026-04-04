defmodule SloPitch.Repo.Migrations.AddEndBasesToPlateAppearances do
  use Ecto.Migration

  def change do
    alter table(:plate_appearances) do
      add :end_bases, :map
    end
  end
end
