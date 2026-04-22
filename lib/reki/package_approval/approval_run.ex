defmodule Reki.PackageApproval.ApprovalRun do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "approval_runs" do
    field :status, Ecto.Enum, values: [:queued, :running, :passed, :failed, :errored, :cancelled]

    field :started_at, :utc_datetime
    field :finished_at, :utc_datetime
    field :command_set_digest, :string
    field :summary, :map, default: %{}

    belongs_to :package_version, Reki.Packages.PackageVersion
    has_many :steps, Reki.PackageApproval.ApprovalRunStep

    timestamps(type: :utc_datetime)
  end

  def changeset(run, attrs) do
    run
    |> cast(attrs, [
      :package_version_id,
      :status,
      :started_at,
      :finished_at,
      :command_set_digest,
      :summary
    ])
    |> validate_required([:package_version_id, :status, :command_set_digest])
    |> assoc_constraint(:package_version)
  end
end
