defmodule RekiWeb.PackageJSON do
  alias Reki.Packages.Package

  @doc """
  Renders a list of packages.
  """
  def index(%{packages: packages}) do
    %{data: for(package <- packages, do: data(package))}
  end

  @doc """
  Renders a single package.
  """
  def show(%{package: package}) do
    %{data: data(package)}
  end

  defp data(%Package{} = package) do
    %{
      id: package.id,
      title: package.title
    }
  end
end
