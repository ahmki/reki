defmodule Reki.Packages do
  import Ecto.Query

  alias Reki.Repo
  alias Reki.Packages.{Package, PackageVersion}

  # ── Fetch ──────────────────────────────────────────────────────────────────

  def get_packument(name) do
    case get_package(name) do
      nil -> {:error, :not_found}
      pkg -> {:ok, build_packument(pkg)}
    end
  end

  def get_version(name, version) do
    result =
      Repo.one(
        from v in PackageVersion,
          join: p in assoc(v, :package),
          where: p.name == ^name and v.version == ^version and v.validation_status == :approved
      )

    case result do
      nil -> {:error, :not_found}
      v -> {:ok, build_version_manifest(v)}
    end
  end

  def get_tarball(name, filename) do
    key = "#{name}/-/#{filename}"
    version = version_from_filename(name, filename)

    with true <- String.ends_with?(filename, ".tgz"),
         true <- tarball_matches?(name, version),
         {:ok, data} <- Reki.Storage.get(key) do
      {:ok, data}
    else
      false -> {:error, :not_found}
      {:error, :enoent} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  # ── Publish ────────────────────────────────────────────────────────────────

  def publish(name, body) do
    with {:ok, version, manifest, tarball} <- extract_publish_payload(name, body),
         :ok <- validate_manifest(name, version, manifest),
         {:ok, url, shasum, integrity, size} <- store_tarball(name, version, tarball),
         {:ok, vsn} <- publish_version(name, version, manifest, url, shasum, integrity, size) do
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
      "_id" => pkg.name,
      "name" => pkg.name,
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

  defp extract_publish_payload(name, body) do
    version = get_in(body, ["dist-tags", "latest"])
    manifest = get_in(body, ["versions", version])
    attachment_key = tarball_filename(name, version)
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

  defp upsert_package(name, version, manifest) do
    Repo.insert(
      %Package{
        name: name,
        latest: version,
        description: manifest["description"],
        dist_tags: %{"latest" => version}
      },
      on_conflict: [set: [latest: version, dist_tags: %{"latest" => version}]],
      conflict_target: :name,
      returning: true
    )
  end

  defp publish_version(name, version, manifest, url, shasum, integrity, size) do
    with {:ok, pkg} <- upsert_package(name, version, manifest) do
      insert_version(pkg.id, version, manifest, url, shasum, integrity, size)
    end
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

  defp store_tarball(name, version, tarball) do
    shasum = :crypto.hash(:sha, tarball) |> Base.encode16(case: :lower)

    integrity =
      :crypto.hash(:sha512, tarball)
      |> Base.encode64()
      |> then(&"sha512-#{&1}")

    size = byte_size(tarball)

    case Reki.Storage.put(tarball_key(name, version), tarball) do
      :ok -> {:ok, tarball_url(name, version), shasum, integrity, size}
      error -> error
    end
  end

  defp get_package(name) do
    Repo.one(
      from p in Package,
        where: p.name == ^name,
        preload: :versions
    )
  end

  defp validate_manifest(name, version, manifest) do
    with ^name <- manifest["name"],
         ^version <- manifest["version"] do
      :ok
    else
      _ -> {:error, :invalid_payload}
    end
  end

  defp tarball_matches?(name, filename) do
    Repo.exists?(
      from v in PackageVersion,
        join: p in assoc(v, :package),
        where:
          p.name == ^name and v.validation_status == :approved and
            v.version == ^filename
    )
  end

  defp version_from_filename(name, filename) do
    filename
    |> String.trim_leading("#{package_slug(name)}-")
    |> String.trim_trailing(".tgz")
  end

  defp tarball_url(name, version),
    do: "/api/#{URI.encode(name)}/-/#{tarball_filename(name, version)}"

  defp tarball_key(name, version), do: "#{name}/-/#{tarball_filename(name, version)}"

  defp tarball_filename(name, version), do: "#{package_slug(name)}-#{version}.tgz"

  defp package_slug(name) do
    name
    |> String.split("/")
    |> List.last()
  end
end
