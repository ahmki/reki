defmodule Reki.Packages do
  import Ecto.Query
  alias Reki.Repo
  alias Reki.Packages.{Package, PackageVersion}

  # ── Fetch ──────────────────────────────────────────────────────────────────

  def get_packument(title) do
    case get_package(title) do
      nil -> {:error, :not_found}
      pkg -> {:ok, build_packument(pkg)}
    end
  end

  def get_version(title, version) do
    result =
      Repo.one(
        from v in PackageVersion,
          join: p in assoc(v, :package),
          where: p.title == ^title and v.version == ^version
      )

    case result do
      nil -> {:error, :not_found}
      v -> {:ok, build_version_manifest(v)}
    end
  end

  # ── Publish ────────────────────────────────────────────────────────────────

  def publish(title, body) do
    with {:ok, version, manifest, tarball} <- extract_publish_payload(title, body),
         {:ok, url, shasum, integrity, size} <- store_tarball(title, version, tarball),
         {:ok, pkg} <- upsert_package(title, version, manifest),
         {:ok, vsn} <- insert_version(pkg.id, version, manifest, url, shasum, integrity, size) do
      {:ok, vsn}
    end
  end

  # ── Packument builder ──────────────────────────────────────────────────────

  defp build_packument(%Package{} = pkg) do
    approved_versions =
      pkg.versions
      |> Enum.filter(&(&1.validation_status == :approved))
      |> Map.new(&{&1.version, build_version_manifest(&1)})

    %{
      "_id" => pkg.title,
      "title" => pkg.title,
      "description" => pkg.description,
      "dist-tags" => pkg.dist_tags,
      "versions" => approved_versions,
      "time" => build_time_map(pkg.versions)
    }
  end

  defp build_version_manifest(%PackageVersion{} = v) do
    Map.merge(v.manifest, %{
      "dist" => %{
        "tarball" => v.tarball_url,
        "shasum" => v.shasum,
        "integrity" => v.integrity,
        "fileCount" => v.tarball_size
      }
    })
  end

  defp build_time_map(versions) do
    Map.new(versions, fn v ->
      {v.version, DateTime.to_iso8601(v.inserted_at)}
    end)
  end

  # ── Publish helpers ────────────────────────────────────────────────────────

  defp extract_publish_payload(title, body) do
    version = get_in(body, ["dist-tags", "latest"])
    manifest = get_in(body, ["versions", version])
    attachment_key = "#{title}-#{version}.tgz"
    tarball_b64 = get_in(body, ["_attachments", attachment_key, "data"])

    with false <- is_nil(version),
         false <- is_nil(manifest),
         false <- is_nil(tarball_b64),
         {:ok, tarball} <- Base.decode64(tarball_b64) do
      {:ok, version, manifest, tarball}
    else
      true -> {:error, :invalid_payload}
      :error -> {:error, :invalid_tarball_encoding}
    end
  end

  defp upsert_package(title, version, manifest) do
    Repo.insert(
      %Package{
        title: title,
        latest: version,
        description: manifest["description"],
        dist_tags: %{"latest" => version}
      },
      on_conflict: [set: [latest: version, dist_tags: %{"latest" => version}]],
      conflict_target: :title,
      returning: true
    )
  end

  defp insert_version(package_id, version, manifest, url, shasum, integrity, size) do
    %PackageVersion{}
    |> PackageVersion.changeset(%{
      package_id: package_id,
      version: version,
      manifest: manifest,
      tarball_url: url,
      shasum: shasum,
      integrity: integrity,
      tarball_size: size,
      validation_status: :pending
    })
    |> Repo.insert()
  end

  defp store_tarball(title, version, tarball) do
    shasum = :crypto.hash(:sha, tarball) |> Base.encode16(case: :lower)

    integrity =
      :crypto.hash(:sha512, tarball)
      |> Base.encode64()
      |> then(&"sha512-#{&1}")

    size = byte_size(tarball)

    case Reki.Storage.put(tarball_key(title, version), tarball) do
      {:ok, url} -> {:ok, url, shasum, integrity, size}
      error -> error
    end
  end

  defp get_package(title) do
    Repo.one(
      from p in Package,
        where: p.title == ^title,
        preload: :versions
    )
  end

  defp tarball_key(title, version), do: "#{title}/-/#{title}-#{version}.tgz"
end
