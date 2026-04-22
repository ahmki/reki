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

  def publish_payload(
        name,
        version,
        tarball_or_files \\ nil
      ) do
    filename = tarball_filename(name, version)

    tarball =
      tarball_or_files
      |> Kernel.||(default_package_files(name, version))
      |> tarball_from_fixture()

    %{
      "dist-tags" => %{"latest" => version},
      "versions" => %{
        version => %{
          "name" => name,
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

  def package_tarball(files) when is_map(files) do
    root =
      Path.join(System.tmp_dir!(), "reki-package-fixture-#{System.unique_integer([:positive])}")

    package_root = Path.join(root, "build")
    tar_path = Path.join(root, "package.tgz")

    File.mkdir_p!(package_root)

    Enum.each(files, fn {path, contents} ->
      full_path = Path.join(package_root, path)
      File.mkdir_p!(Path.dirname(full_path))
      File.write!(full_path, contents)
    end)

    {"", 0} =
      System.cmd("tar", ["-czf", tar_path, "-C", package_root, "package"], stderr_to_stdout: true)

    tarball = File.read!(tar_path)
    File.rm_rf!(root)
    tarball
  end

  def tarball_filename(name, version) do
    "#{name |> String.split("/") |> List.last()}-#{version}.tgz"
  end

  defp tarball_from_fixture(files) when is_map(files), do: package_tarball(files)
  defp tarball_from_fixture(tarball) when is_binary(tarball), do: tarball

  defp default_package_files(name, version) do
    %{"package/package.json" => ~s({"name":"#{name}","version":"#{version}"})}
  end
end
