defmodule Reki.Repo.Migrations.CreatePackageVersions do
  use Ecto.Migration

  def change do
    create table(:package_versions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :package_id, references(:packages, type: :binary_id, on_delete: :delete_all), null: false
      add :version, :string, null: false
      add :manifest, :map, null: false
      add :shasum, :string
      add :integrity, :string
      add :tarball_url, :string
      add :tarball_size, :integer
      add :validation_status, :string, default: "pending", null: false
      add :validation_results, :map, default: %{}

      timestamps()
    end

    create unique_index(:package_versions, [:package_id, :version])
    create index(:package_versions, [:package_id])
    create index(:package_versions, [:validation_status])
  end
end
