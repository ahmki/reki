defmodule Reki.PackagesFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Reki.Packages` context.
  """

  @doc """
  Generate a package.
  """
  def package_fixture(attrs \\ %{}) do
    {:ok, package} =
      attrs
      |> Enum.into(%{
        title: "some title"
      })
      |> Reki.Packages.create_package()

    package
  end
end
