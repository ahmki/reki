defmodule Reki.Packages.Package do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "packages" do
    field :name, :string
    field :latest, :string
    field :description, :string
    field :dist_tags, :map, default: %{}

    has_many :versions, Reki.Packages.PackageVersion

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(package, attrs) do
    package
    |> cast(attrs, [:name, :latest, :description, :dist_tags])
    |> validate_required([:name])
    |> unique_constraint(:name)
  end
end
