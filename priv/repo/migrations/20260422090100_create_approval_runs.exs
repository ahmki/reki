defmodule Reki.Repo.Migrations.CreateApprovalRuns do
  use Ecto.Migration

  def change do
    create table(:approval_runs, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :package_version_id,
          references(:package_versions, type: :binary_id, on_delete: :delete_all),
          null: false

      add :status, :string, null: false
      add :started_at, :utc_datetime
      add :finished_at, :utc_datetime
      add :command_set_digest, :string, null: false
      add :summary, :map, default: %{}, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:approval_runs, [:package_version_id])
    create index(:approval_runs, [:package_version_id, :inserted_at])
    create index(:approval_runs, [:package_version_id, :status])
  end
end
