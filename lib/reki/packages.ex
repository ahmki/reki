defmodule Reki.Packages do
  import Ecto.Query

  alias Reki.Repo
  alias Reki.Packages.{Package, PackageVersion}
  alias Reki.PackageApproval

  @catalog_topic "packages:catalog"

  # ── Fetch ──────────────────────────────────────────────────────────────────

  def list_packages_for_catalog do
    Package
    |> order_by([p], asc: p.name)
    |> preload(
      versions:
        ^from(v in PackageVersion,
          order_by: [desc: v.inserted_at, desc: v.version],
          preload: [
            approval_runs:
              ^from(run in Reki.PackageApproval.ApprovalRun, order_by: [desc: run.inserted_at])
          ]
        )
    )
    |> Repo.all()
    |> Enum.map(&build_catalog_entry/1)
  end

  defp versions_with_approval_runs_query do
    from v in PackageVersion,
      order_by: [desc: v.inserted_at, desc: v.version],
      preload: [
        approval_runs:
          ^from(run in Reki.PackageApproval.ApprovalRun,
            order_by: [desc: run.inserted_at],
            preload: [
              steps:
                ^from(step in Reki.PackageApproval.ApprovalRunStep,
                  order_by: [asc: step.inserted_at]
                )
            ]
          )
      ]
  end

  def get_package_for_catalog(name) do
    query = from p in Package,
      where: p.name == ^name,
      preload: [versions: ^versions_with_approval_runs_query()]

    case Repo.one(query) do
      nil -> {:error, :not_found}
      package -> {:ok, build_package_detail(package)}
    end
  end

  def get_package_version_for_catalog(name, version) do
    versions_query =
      versions_with_approval_runs_query()
      |> where([v], v.version == ^version)

    query = from p in Package,
      where: p.name == ^name,
      preload: [versions: ^versions_query]

    case Repo.one(query) do
      %Package{versions: [package_version]} = package ->
        {:ok, %{
          package: build_catalog_entry(package),
          version: build_catalog_version(package_version)
        }}

      _ ->
        {:error, :not_found}
    end
  end
  def subscribe_catalog do
    Phoenix.PubSub.subscribe(Reki.PubSub, @catalog_topic)
  end

  def broadcast_catalog_updated do
    Phoenix.PubSub.broadcast(Reki.PubSub, @catalog_topic, :catalog_updated)
  end

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
      broadcast_catalog_updated()
      {:ok, vsn}
    end
  end

  def request_approval(name, version) do
    case get_package_version(name, version) do
      nil -> {:error, :not_found}
      package_version -> PackageApproval.request(package_version)
    end
  end

  def approve_version(name, version) do
    decide_version(name, version, :approved)
  end

  def block_version(name, version) do
    decide_version(name, version, :blocked)
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

  defp build_catalog_entry(%Package{} = package) do
    versions =
      Enum.sort_by(package.versions, &{DateTime.to_unix(&1.inserted_at), &1.version}, :desc)

    latest_version = List.first(versions)
    approved_version = Enum.find(versions, &(&1.validation_status == :approved))
    total_versions = length(versions)
    latest_run = latest_version && latest_approval_run(latest_version)

    %{
      id: package.id,
      name: package.name,
      description: package.description,
      latest: package.latest,
      total_versions: total_versions,
      approved_versions: count_versions(versions, :approved),
      pending_versions: count_versions(versions, :pending),
      blocked_versions: count_versions(versions, :blocked),
      latest_published_at: latest_version && latest_version.inserted_at,
      latest_release_status: latest_release_status(latest_version, latest_run),
      latest_approved_version: approved_version && approved_version.version,
      latest_approved_at: approved_version && approved_version.inserted_at
    }
  end

  defp build_package_detail(%Package{} = package) do
    catalog_entry = build_catalog_entry(package)
    versions = Enum.map(package.versions, &build_catalog_version/1)
    Map.put(catalog_entry, :versions, versions)
  end

  defp count_versions(versions, status) do
    Enum.count(versions, &(&1.validation_status == status))
  end

  defp latest_approval_run(%PackageVersion{} = version) do
    version.approval_runs
    |> Enum.sort_by(&{DateTime.to_unix(&1.inserted_at), &1.id}, :desc)
    |> List.first()
  end

  defp build_catalog_version(%PackageVersion{} = version) do
    latest_run = latest_approval_run(version)

    %{
      id: version.id,
      version: version.version,
      inserted_at: version.inserted_at,
      validation_status: version.validation_status,
      tarball_size: version.tarball_size,
      shasum: version.shasum,
      integrity: version.integrity,
      latest_run: build_catalog_run(latest_run)
    }
  end

  defp build_catalog_run(nil), do: nil

  defp build_catalog_run(run) do
    %{
      id: run.id,
      status: run.status,
      inserted_at: run.inserted_at,
      started_at: run.started_at,
      finished_at: run.finished_at,
      summary: run.summary,
      steps: Enum.map(run.steps, &build_catalog_step/1)
    }
  end

  defp build_catalog_step(step) do
    %{
      id: step.id,
      name: step.name,
      status: step.status,
      exit_code: step.exit_code,
      command: step.command,
      stdout: step.stdout,
      stderr: step.stderr,
      started_at: step.started_at,
      finished_at: step.finished_at
    }
  end

  defp latest_release_status(nil, _latest_run), do: :none
  defp latest_release_status(_version, %{status: :queued}), do: :queued
  defp latest_release_status(_version, %{status: :running}), do: :running
  defp latest_release_status(%PackageVersion{validation_status: status}, _latest_run), do: status

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

  defp get_package_version(name, version) do
    Repo.one(
      from v in PackageVersion,
        join: p in assoc(v, :package),
        where: p.name == ^name and v.version == ^version
    )
  end

  defp decide_version(name, version, status) do
    case get_package_version(name, version) do
      nil ->
        {:error, :not_found}

      %PackageVersion{validation_status: current_status} = package_version
      when current_status == status ->
        {:ok, package_version}

      %PackageVersion{validation_status: current_status}
      when current_status in [:approved, :blocked] ->
        {:error, :already_decided}

      %PackageVersion{} = package_version ->
        package_version
        |> Ecto.Changeset.change(validation_status: status)
        |> Repo.update()
        |> case do
          {:ok, updated} ->
            broadcast_catalog_updated()
            {:ok, updated}

          error ->
            error
        end
    end
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
