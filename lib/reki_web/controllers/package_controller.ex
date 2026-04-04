defmodule RekiWeb.PackageController do
  use RekiWeb, :controller

  alias Reki.Packages
  alias Reki.Packages.Package

  action_fallback RekiWeb.FallbackController

  def index(conn, _params) do
    packages = Packages.list_packages()
    render(conn, :index, packages: packages)
  end

  def create(conn, %{"package" => package_params}) do
    with {:ok, %Package{} = package} <- Packages.create_package(package_params) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", ~p"/api/packages/#{package}")
      |> render(:show, package: package)
    end
  end

  def show(conn, %{"id" => id}) do
    package = Packages.get_package!(id)
    render(conn, :show, package: package)
  end

  def update(conn, %{"id" => id, "package" => package_params}) do
    package = Packages.get_package!(id)

    with {:ok, %Package{} = package} <- Packages.update_package(package, package_params) do
      render(conn, :show, package: package)
    end
  end

  def delete(conn, %{"id" => id}) do
    package = Packages.get_package!(id)

    with {:ok, %Package{}} <- Packages.delete_package(package) do
      send_resp(conn, :no_content, "")
    end
  end
end
