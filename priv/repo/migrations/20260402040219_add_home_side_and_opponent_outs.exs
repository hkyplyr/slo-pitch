defmodule SloPitch.Repo.Migrations.AddHomeSideAndOpponentOuts do
  use Ecto.Migration

  def change do
    alter table(:games) do
      add :home_or_away, :string, null: false, default: "away"
    end

    alter table(:game_innings) do
      add :opp_outs, :integer, null: false, default: 0
    end
  end
end
