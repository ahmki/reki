defmodule RekiWeb.PackageControllerTest do
  use RekiWeb.ConnCase
  use Oban.Testing, repo: Reki.Repo

  import Ecto.Query
  import Reki.PackagesFixtures

  alias Reki.PackageApproval.Worker

  setup %{conn: conn} do
    File.rm_rf!(storage_root())
    put_package_approval_steps([])

    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  describe "publish and install endpoints" do
    test "pending releases cannot be installed until approved", %{conn: conn} do
      name = "widget"
      version = "1.0.0"

      tarball =
        package_tarball(%{"package/package.json" => ~s({"name":"widget","version":"1.0.0"})})

      put_package_approval_steps([
        %{
          name: "package-json-check",
          command: "elixir",
          args: ["-e", "File.read!(\"package.json\") |> IO.write()"],
          timeout: 5_000,
          blocking: true
        }
      ])

      conn =
        put(
          conn,
          ~p"/api/#{name}",
          publish_payload(name, version, tarball)
        )

      assert %{"ok" => true, "id" => "widget@1.0.0"} = json_response(conn, 201)

      conn = get(build_conn(), ~p"/api/#{name}/#{version}")
      assert %{"error" => "Not found: widget@1.0.0"} = json_response(conn, 404)

      conn = get(build_conn(), ~p"/api/#{name}/-/widget-1.0.0.tgz")
      assert %{"error" => "Not found: widget-1.0.0.tgz"} = json_response(conn, 404)

      conn = post(build_conn(), ~p"/api/#{name}/#{version}/approval")
      assert %{"ok" => true, "id" => "widget@1.0.0"} = json_response(conn, 202)

      assert :ok =
               perform_job(Worker, %{
                 "package_version_id" => published_package_version_id(name, version)
               })

      conn = get(build_conn(), ~p"/api/#{name}/#{version}")

      assert %{
               "name" => "widget",
               "version" => "1.0.0",
               "dist" => %{
                 "shasum" => shasum,
                 "integrity" => integrity,
                 "tarball" => "/api/widget/-/widget-1.0.0.tgz"
               }
             } = json_response(conn, 200)

      assert shasum == sha1(tarball)
      assert integrity == sha512(tarball)

      conn = get(build_conn(), ~p"/api/#{name}/-/widget-1.0.0.tgz")
      assert response(conn, 200) == tarball
    end

    test "publish rejects mismatched manifests", %{conn: conn} do
      conn =
        put(
          conn,
          ~p"/api/widget",
          publish_payload("other-package", "1.0.0")
        )

      assert %{"error" => "Invalid publish payload"} = json_response(conn, 400)
    end

    test "approval request returns 404 for unknown versions", %{conn: conn} do
      conn = post(conn, ~p"/api/widget/1.0.0/approval")

      assert %{"error" => "Not found: widget@1.0.0"} = json_response(conn, 404)
    end
  end

  defp storage_root do
    Application.fetch_env!(:reki, Reki.Storage)
    |> Keyword.fetch!(:root)
  end

  defp published_package_version_id(name, version) do
    Reki.Repo.one!(
      from v in Reki.Packages.PackageVersion,
        join: p in assoc(v, :package),
        where: p.name == ^name and v.version == ^version,
        select: v.id
    )
  end

  defp put_package_approval_steps(steps) do
    previous = Application.get_env(:reki, :package_approval_steps, [])
    Application.put_env(:reki, :package_approval_steps, steps)
    on_exit(fn -> Application.put_env(:reki, :package_approval_steps, previous) end)
  end

  defp sha1(data) do
    :crypto.hash(:sha, data)
    |> Base.encode16(case: :lower)
  end

  defp sha512(data) do
    :crypto.hash(:sha512, data)
    |> Base.encode64()
    |> then(&"sha512-#{&1}")
  end
end
