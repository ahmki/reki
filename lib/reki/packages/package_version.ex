defmodule Reki.Packages.PackageVersion do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "package_versions" do
    field :version, :string
    field :manifest, :map
    field :tarball_url, :string
    field :tarball_size, :integer
    field :shasum, :string
    field :integrity, :string
    field :validation_results, :map, default: %{}

    field :validation_status, Ecto.Enum,
      values: [:pending, :approved, :blocked],
      default: :pending

    belongs_to :package, Reki.Packages.Package

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(version, attrs) do
    version
    |> cast(attrs, [
      :package_id,
      :version,
      :manifest,
      :tarball_url,
      :tarball_size,
      :shasum,
      :integrity,
      :validation_status,
      :validation_results
    ])
    |> validate_required([:package_id, :version, :manifest])
    |> assoc_constraint(:package)
    |> unique_constraint([:package_id, :version])
  end
end
