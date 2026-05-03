defmodule RekiWeb.PageController do
  use RekiWeb, :controller

  alias Reki.Packages

  def home(conn, _params) do
    packages = Packages.list_packages_for_catalog()

    stats = %{
      package_count: length(packages),
      approved_count: Enum.count(packages, &(&1.approved_versions > 0)),
      pending_count: Enum.sum(Enum.map(packages, & &1.pending_versions)),
      blocked_count: Enum.sum(Enum.map(packages, & &1.blocked_versions))
    }

    render(conn, :home, packages: packages, stats: stats)
  end
end
