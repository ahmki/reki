defmodule RekiWeb.PackageImportControllerTest do
  use RekiWeb.ConnCase
  use Oban.Testing, repo: Reki.Repo

  import Ecto.Query
  import Reki.PackagesFixtures

  alias Reki.PackageApproval.Worker

  setup %{conn: conn} do
    File.rm_rf!(storage_root())
    put_upstream_registry_client(Reki.TestUpstreamRegistry)
    put_upstream_registry_responses(%{})

    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  test "imports a mirrored package version and queues approval", %{conn: conn} do
    name = "@scope/controller-widget"
    version = "2.0.0"
    {:ok, manifest, tarball} = upstream_release(name, version)

    put_upstream_registry_responses(%{{name, version} => {:ok, manifest, tarball}})

    conn = post(conn, ~p"/api/imports", %{"name" => name, "version" => version})

    assert %{"ok" => true, "id" => "@scope/controller-widget@2.0.0"} = json_response(conn, 202)

    package_version_id =
      Reki.Repo.one!(
        from v in Reki.Packages.PackageVersion,
          join: p in assoc(v, :package),
          where: p.name == ^name and v.version == ^version,
          select: v.id
      )

    assert_enqueued(worker: Worker, args: %{"package_version_id" => package_version_id})
  end

  test "returns 404 when upstream package is missing", %{conn: conn} do
    conn = post(conn, ~p"/api/imports", %{"name" => "missing-package", "version" => "1.0.0"})

    assert %{"error" => "Upstream package not found: missing-package"} = json_response(conn, 404)
  end

  test "returns 404 when upstream version is missing", %{conn: conn} do
    put_upstream_registry_responses(%{
      {"missing-version", "7.0.0"} => {:error, :version_not_found}
    })

    conn = post(conn, ~p"/api/imports", %{"name" => "missing-version", "version" => "7.0.0"})

    assert %{"error" => "Upstream version not found: missing-version@7.0.0"} =
             json_response(conn, 404)
  end

  test "returns 409 when the version already exists locally", %{conn: conn} do
    assert {:ok, _package_version} =
             Reki.Packages.publish(
               "duplicate-widget",
               publish_payload("duplicate-widget", "1.0.0")
             )

    conn = post(conn, ~p"/api/imports", %{"name" => "duplicate-widget", "version" => "1.0.0"})

    assert %{"error" => "Package version already exists: duplicate-widget@1.0.0"} =
             json_response(conn, 409)
  end

  test "returns 422 for malformed requests", %{conn: conn} do
    conn = post(conn, ~p"/api/imports", %{"name" => "widget"})

    assert %{"error" => "Expected package name and exact version"} = json_response(conn, 422)
  end

  defp storage_root do
    Application.fetch_env!(:reki, Reki.Storage)
    |> Keyword.fetch!(:root)
  end

  defp put_upstream_registry_client(client) do
    previous = Application.get_env(:reki, :upstream_registry_client)
    Application.put_env(:reki, :upstream_registry_client, client)
    on_exit(fn -> restore_env(:upstream_registry_client, previous) end)
  end

  defp put_upstream_registry_responses(responses) do
    previous = Application.get_env(:reki, :test_upstream_registry_responses)
    Application.put_env(:reki, :test_upstream_registry_responses, responses)
    on_exit(fn -> restore_env(:test_upstream_registry_responses, previous) end)
  end

  defp restore_env(key, nil), do: Application.delete_env(:reki, key)
  defp restore_env(key, value), do: Application.put_env(:reki, key, value)
end
