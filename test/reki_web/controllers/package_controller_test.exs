defmodule RekiWeb.PackageControllerTest do
  use RekiWeb.ConnCase

  import Ecto.Query

  alias Reki.Packages.PackageVersion
  alias Reki.Repo

  setup %{conn: conn} do
    File.rm_rf!(storage_root())

    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  describe "publish and install endpoints" do
    test "pending releases cannot be installed until approved", %{conn: conn} do
      title = "widget"
      version = "1.0.0"
      tarball = "controller-tarball"

      conn = put(conn, ~p"/api/#{title}", publish_payload(title, version, tarball))
      assert %{"ok" => true, "id" => "widget@1.0.0"} = json_response(conn, 201)

      conn = get(build_conn(), ~p"/api/#{title}/#{version}")
      assert %{"error" => "Not found: widget@1.0.0"} = json_response(conn, 404)

      conn = get(build_conn(), ~p"/api/#{title}/-/widget-1.0.0.tgz")
      assert %{"error" => "Not found: widget-1.0.0.tgz"} = json_response(conn, 404)

      approve_version(title, version)

      conn = get(build_conn(), ~p"/api/#{title}/#{version}")

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

      conn = get(build_conn(), ~p"/api/#{title}/-/widget-1.0.0.tgz")
      assert response(conn, 200) == tarball
    end

    test "publish rejects mismatched manifests", %{conn: conn} do
      conn =
        put(
          conn,
          ~p"/api/widget",
          publish_payload("other-package", "1.0.0", "tarball")
        )

      assert %{"error" => "Invalid publish payload"} = json_response(conn, 400)
    end
  end

  defp publish_payload(title, version, tarball) do
    filename = "#{title |> String.split("/") |> List.last()}-#{version}.tgz"

    %{
      "dist-tags" => %{"latest" => version},
      "versions" => %{
        version => %{
          "name" => title,
          "version" => version,
          "description" => "Controller test package"
        }
      },
      "_attachments" => %{
        filename => %{
          "data" => Base.encode64(tarball)
        }
      }
    }
  end

  defp approve_version(title, version) do
    from(v in PackageVersion,
      join: p in assoc(v, :package),
      where: p.title == ^title and v.version == ^version
    )
    |> Repo.update_all(set: [validation_status: :approved])
  end

  defp storage_root do
    Application.fetch_env!(:reki, Reki.Storage)
    |> Keyword.fetch!(:root)
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
