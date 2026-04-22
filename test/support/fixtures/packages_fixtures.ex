defmodule Reki.PackagesFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Reki.Packages` context.
  """

  alias Reki.Packages.Package
  alias Reki.Repo

  @doc """
  Generate a package.
  """
  def package_fixture(attrs \\ %{}) do
    attrs
    |> Enum.into(%{name: "some package"})
    |> then(&Package.changeset(%Package{}, &1))
    |> Repo.insert!()
  end
end
