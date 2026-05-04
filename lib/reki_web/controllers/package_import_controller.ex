defmodule RekiWeb.PackageImportController do
  use RekiWeb, :controller

  alias Reki.Packages

  def create(conn, %{"name" => name, "version" => version})
      when is_binary(name) and is_binary(version) do
    case Packages.import_from_upstream(name, version) do
      {:ok, package_version} ->
        conn
        |> put_status(:accepted)
        |> json(%{ok: true, id: "#{name}@#{package_version.version}"})

      {:error, :upstream_not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Upstream package not found: #{name}"})

      {:error, :upstream_version_not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Upstream version not found: #{name}@#{version}"})

      {:error, :already_exists} ->
        conn
        |> put_status(:conflict)
        |> json(%{error: "Package version already exists: #{name}@#{version}"})

      {:error, :invalid_upstream_payload} ->
        conn
        |> put_status(:bad_gateway)
        |> json(%{error: "Upstream registry returned an invalid package payload"})

      {:error, :upstream_tarball_not_found} ->
        conn
        |> put_status(:bad_gateway)
        |> json(%{error: "Upstream tarball could not be downloaded"})

      {:error, reason} ->
        conn
        |> put_status(:bad_gateway)
        |> json(%{error: inspect(reason)})
    end
  end

  def create(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "Expected package name and exact version"})
  end
end
