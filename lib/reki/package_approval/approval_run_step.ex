defmodule Reki.PackageApproval.ApprovalRunStep do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "approval_run_steps" do
    field :name, :string
    field :command, :map, default: %{}

    field :status, Ecto.Enum, values: [:passed, :failed, :errored, :skipped, :timed_out]

    field :exit_code, :integer
    field :stdout, :string, default: ""
    field :stderr, :string, default: ""
    field :started_at, :utc_datetime
    field :finished_at, :utc_datetime

    belongs_to :approval_run, Reki.PackageApproval.ApprovalRun

    timestamps(type: :utc_datetime)
  end

  def changeset(step, attrs) do
    step
    |> cast(attrs, [
      :approval_run_id,
      :name,
      :command,
      :status,
      :exit_code,
      :stdout,
      :stderr,
      :started_at,
      :finished_at
    ])
    |> validate_required([:approval_run_id, :name, :command, :status])
    |> assoc_constraint(:approval_run)
  end
end
