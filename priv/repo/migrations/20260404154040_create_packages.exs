defmodule Reki.Repo.Migrations.CreatePackages do
  use Ecto.Migration

  def change do
    create table(:packages, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string, null: false
      add :latest, :string
      add :description, :text
      add :dist_tags, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:packages, [:title])
  end
end
