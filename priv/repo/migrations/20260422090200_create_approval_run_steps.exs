defmodule Reki.Repo.Migrations.CreateApprovalRunSteps do
  use Ecto.Migration

  def change do
    create table(:approval_run_steps, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :approval_run_id,
          references(:approval_runs, type: :binary_id, on_delete: :delete_all),
          null: false

      add :name, :string, null: false
      add :command, :map, default: %{}, null: false
      add :status, :string, null: false
      add :exit_code, :integer
      add :stdout, :text, default: "", null: false
      add :stderr, :text, default: "", null: false
      add :started_at, :utc_datetime
      add :finished_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:approval_run_steps, [:approval_run_id])
    create index(:approval_run_steps, [:approval_run_id, :inserted_at])
  end
end
