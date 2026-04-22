defmodule Reki.PackagesTest do
  use Reki.DataCase

  import Ecto.Query

  alias Reki.Packages
  alias Reki.Packages.PackageVersion
  alias Reki.Repo

  setup do
    File.rm_rf!(storage_root())
    :ok
  end

  describe "publish/2" do
    test "persists integrity data and hides pending versions from installs" do
      title = "widget"
      version = "1.0.0"
      tarball = "package-tarball"

      assert {:ok, %PackageVersion{} = package_version} =
               Packages.publish(title, publish_payload(title, version, tarball))

      assert package_version.validation_status == :pending
      assert package_version.shasum == sha1(tarball)
      assert package_version.integrity == sha512(tarball)

      persisted = Repo.get!(PackageVersion, package_version.id)
      assert persisted.shasum == sha1(tarball)
      assert persisted.integrity == sha512(tarball)

      assert {:error, :not_found} = Packages.get_version(title, version)

      assert {:ok, packument} = Packages.get_packument(title)
      assert packument["versions"] == %{}
    end

    test "approved versions are installable and tarballs remain protected by approval" do
      title = "@scope/widget"
      version = "1.0.0"
      tarball = "approved-tarball"

      assert {:ok, %PackageVersion{}} =
               Packages.publish(title, publish_payload(title, version, tarball))

      assert {:error, :not_found} = Packages.get_tarball(title, "widget-1.0.0.tgz")

      approve_version(title, version)

      assert {:ok, manifest} = Packages.get_version(title, version)
      assert manifest["name"] == title
      assert manifest["version"] == version
      assert manifest["dist"]["shasum"] == sha1(tarball)
      assert manifest["dist"]["integrity"] == sha512(tarball)

      assert {:ok, downloaded} = Packages.get_tarball(title, "widget-1.0.0.tgz")
      assert downloaded == tarball
    end
  end

  defp publish_payload(title, version, tarball) do
    filename = tarball_filename(title, version)

    %{
      "dist-tags" => %{"latest" => version},
      "versions" => %{
        version => %{
          "name" => title,
          "version" => version,
          "description" => "Test package"
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

  defp tarball_filename(title, version) do
    "#{title |> String.split("/") |> List.last()}-#{version}.tgz"
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
