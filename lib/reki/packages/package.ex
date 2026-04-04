defmodule Reki.Packages.Package do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "packages" do
    field :title, :string
    field :latest, :string
    field :description, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(package, attrs) do
    package
    |> cast(attrs, [:title])
    |> validate_required([:title])
    |> unique_constraint(:title)
  end
end
