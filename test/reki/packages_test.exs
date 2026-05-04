defmodule Reki.PackagesTest do
  use Reki.DataCase
  use Oban.Testing, repo: Reki.Repo

  import Ecto.Query
  import Reki.PackagesFixtures

  alias Reki.PackageApproval
  alias Reki.PackageApproval.{ApprovalRun, Worker}
  alias Reki.Packages
  alias Reki.Packages.PackageVersion
  alias Reki.Repo

  setup do
    File.rm_rf!(storage_root())
    put_package_approval_steps([])
    put_upstream_registry_client(Reki.TestUpstreamRegistry)
    put_upstream_registry_responses(%{})
    :ok
  end

  describe "publish/2" do
    test "persists integrity data, hides pending versions from installs, and does not enqueue approval" do
      name = "widget"
      version = "1.0.0"

      tarball =
        package_tarball(%{"package/package.json" => ~s({"name":"widget","version":"1.0.0"})})

      assert {:ok, %PackageVersion{} = package_version} =
               Packages.publish(name, publish_payload(name, version, tarball))

      assert package_version.validation_status == :pending
      assert package_version.shasum == sha1(tarball)
      assert package_version.integrity == sha512(tarball)
      refute_enqueued(worker: Worker, args: %{"package_version_id" => package_version.id})

      persisted = Repo.get!(PackageVersion, package_version.id)
      assert persisted.shasum == sha1(tarball)
      assert persisted.integrity == sha512(tarball)

      assert {:error, :not_found} = Packages.get_version(name, version)

      assert {:ok, packument} = Packages.get_packument(name)
      assert packument["versions"] == %{}
    end

    test "versions remain pending after checks and become installable only after manual approval" do
      name = "@scope/widget"
      version = "1.0.0"

      tarball =
        package_tarball(%{
          "package/package.json" => ~s({"name":"#{name}","version":"#{version}"})
        })

      put_package_approval_steps([
        %{
          name: "package-json-check",
          command: "elixir",
          args: ["-e", "File.read!(\"package.json\") |> IO.write()"],
          timeout: 5_000,
          blocking: true
        }
      ])

      assert {:ok, %PackageVersion{} = package_version} =
               Packages.publish(name, publish_payload(name, version, tarball))

      assert {:error, :not_found} = Packages.get_tarball(name, "widget-1.0.0.tgz")
      assert {:ok, _job} = PackageApproval.request(package_version)
      assert :ok = perform_job(Worker, %{"package_version_id" => package_version.id})

      pending = Repo.get!(PackageVersion, package_version.id)
      assert pending.validation_status == :pending
      assert {:error, :not_found} = Packages.get_version(name, version)
      assert {:error, :not_found} = Packages.get_tarball(name, "widget-1.0.0.tgz")

      assert {:ok, _approved_version} = Packages.approve_version(name, version)

      assert {:ok, manifest} = Packages.get_version(name, version)
      assert manifest["name"] == name
      assert manifest["version"] == version
      assert manifest["dist"]["shasum"] == sha1(tarball)
      assert manifest["dist"]["integrity"] == sha512(tarball)

      assert {:ok, downloaded} = Packages.get_tarball(name, "widget-1.0.0.tgz")
      assert downloaded == tarball

      assert %ApprovalRun{status: :passed, steps: [step]} =
               PackageApproval.latest_run(package_version.id)

      assert step.status == :passed
    end

    test "failed checks keep versions pending until manually blocked" do
      name = "blocked-widget"
      version = "1.0.0"

      put_package_approval_steps([
        %{
          name: "fail-check",
          command: "elixir",
          args: ["-e", "IO.write(:stderr, \"denied\"); System.halt(7)"],
          timeout: 5_000,
          blocking: true
        }
      ])

      assert {:ok, %PackageVersion{} = package_version} =
               Packages.publish(name, publish_payload(name, version))

      assert {:ok, _job} = PackageApproval.request(package_version)
      assert :ok = perform_job(Worker, %{"package_version_id" => package_version.id})

      pending = Repo.get!(PackageVersion, package_version.id)
      assert pending.validation_status == :pending
      assert {:error, :not_found} = Packages.get_version(name, version)

      assert %ApprovalRun{status: :failed, steps: [step]} =
               PackageApproval.latest_run(package_version.id)

      assert step.status == :failed
      assert step.exit_code == 7
      assert step.stderr =~ "denied"

      assert {:ok, blocked} = Packages.block_version(name, version)
      assert blocked.validation_status == :blocked
    end

    test "an active run prevents duplicate runs" do
      name = "active-widget"
      version = "1.0.0"

      assert {:ok, %PackageVersion{} = package_version} =
               Packages.publish(name, publish_payload(name, version))

      assert {:ok, _job} = PackageApproval.request(package_version)

      queued_run = PackageApproval.latest_run(package_version.id)

      queued_run
      |> ApprovalRun.changeset(%{
        status: :running,
        started_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })
      |> Repo.update!()

      assert :ok = perform_job(Worker, %{"package_version_id" => package_version.id})

      assert Repo.aggregate(
               from(run in ApprovalRun, where: run.package_version_id == ^package_version.id),
               :count
             ) == 1
    end

    test "request enqueues an approval job" do
      name = "request-widget"
      version = "1.0.0"

      assert {:ok, %PackageVersion{} = package_version} =
               Packages.publish(name, publish_payload(name, version))

      assert {:ok, _job} = PackageApproval.request(package_version)
      assert_enqueued(worker: Worker, args: %{"package_version_id" => package_version.id})
    end
  end

  describe "list_packages_for_catalog/0" do
    test "returns package availability summary for the frontend" do
      assert {:ok, approved} =
               Packages.publish("approved-widget", publish_payload("approved-widget", "1.0.0"))

      Repo.update!(Ecto.Changeset.change(approved, validation_status: :approved))

      assert {:ok, _pending} =
               Packages.publish("approved-widget", publish_payload("approved-widget", "1.1.0"))

      assert {:ok, blocked} =
               Packages.publish("blocked-widget", publish_payload("blocked-widget", "2.0.0"))

      Repo.update!(Ecto.Changeset.change(blocked, validation_status: :blocked))

      [approved_widget, blocked_widget] =
        Packages.list_packages_for_catalog()
        |> Enum.sort_by(& &1.name)

      assert approved_widget.name == "approved-widget"
      assert approved_widget.total_versions == 2
      assert approved_widget.approved_versions == 1
      assert approved_widget.pending_versions == 1
      assert approved_widget.blocked_versions == 0
      assert approved_widget.latest == "1.1.0"
      assert approved_widget.latest_approved_version == "1.0.0"
      assert %DateTime{} = approved_widget.latest_published_at
      assert %DateTime{} = approved_widget.latest_approved_at

      assert blocked_widget.name == "blocked-widget"
      assert blocked_widget.total_versions == 1
      assert blocked_widget.approved_versions == 0
      assert blocked_widget.pending_versions == 0
      assert blocked_widget.blocked_versions == 1
      assert blocked_widget.latest_approved_version == nil
      assert %DateTime{} = blocked_widget.latest_published_at
      assert blocked_widget.latest_approved_at == nil
    end

    test "marks the latest release as queued after approval is requested" do
      assert {:ok, %PackageVersion{} = package_version} =
               Packages.publish("queued-widget", publish_payload("queued-widget", "1.0.0"))

      assert {:ok, _job} = PackageApproval.request(package_version)

      [queued_widget] = Packages.list_packages_for_catalog()

      assert queued_widget.name == "queued-widget"
      assert queued_widget.latest_release_status == :queued
      assert queued_widget.latest_approved_version == nil
      assert PackageApproval.latest_run(package_version.id).status == :queued
    end

    test "includes version runs and captured output" do
      put_package_approval_steps([
        %{
          name: "io-check",
          command: "elixir",
          args: ["-e", "IO.write(\"ok\"); IO.write(:stderr, \"warn\")"],
          timeout: 5_000,
          blocking: true
        }
      ])

      assert {:ok, %PackageVersion{} = package_version} =
               Packages.publish("output-widget", publish_payload("output-widget", "1.0.0"))

      assert {:ok, _job} = PackageApproval.request(package_version)
      assert :ok = perform_job(Worker, %{"package_version_id" => package_version.id})

      assert {:ok, package} = Packages.get_package_for_catalog("output-widget")
      [version] = package.versions
      [step] = version.latest_run.steps

      assert package.name == "output-widget"
      assert version.version == "1.0.0"
      assert version.validation_status == :pending
      assert version.latest_run.status == :passed
      assert step.name == "io-check"
      assert step.stdout == "ok"
      assert step.stderr == "warn"
    end

    test "manual decisions update installability" do
      assert {:ok, _package_version} =
               Packages.publish("decide-widget", publish_payload("decide-widget", "1.0.0"))

      assert {:ok, approved} = Packages.approve_version("decide-widget", "1.0.0")
      assert approved.validation_status == :approved
      assert {:ok, _manifest} = Packages.get_version("decide-widget", "1.0.0")

      assert {:ok, _package_version} =
               Packages.publish(
                 "block-decide-widget",
                 publish_payload("block-decide-widget", "1.0.0")
               )

      assert {:ok, blocked} = Packages.block_version("block-decide-widget", "1.0.0")
      assert blocked.validation_status == :blocked
      assert {:error, :not_found} = Packages.get_version("block-decide-widget", "1.0.0")
    end
  end

  describe "import_from_upstream/2" do
    test "imports a mirrored version, stores integrity data, and queues approval" do
      name = "@scope/mirror-widget"
      version = "1.2.3"
      {:ok, manifest, tarball} = upstream_release(name, version)

      put_upstream_registry_responses(%{{name, version} => {:ok, manifest, tarball}})

      assert {:ok, %PackageVersion{} = package_version} =
               Packages.import_from_upstream(name, version)

      assert package_version.validation_status == :pending
      assert package_version.manifest["name"] == name
      assert package_version.manifest["version"] == version
      assert package_version.shasum == sha1(tarball)
      assert package_version.integrity == sha512(tarball)
      assert_enqueued(worker: Worker, args: %{"package_version_id" => package_version.id})

      assert {:error, :not_found} = Packages.get_version(name, version)
      assert {:error, :not_found} = Packages.get_tarball(name, "mirror-widget-1.2.3.tgz")
      assert %ApprovalRun{status: :queued} = PackageApproval.latest_run(package_version.id)
    end

    test "mirrored versions become installable only after manual approval" do
      name = "approved-mirror"
      version = "4.5.6"
      {:ok, manifest, tarball} = upstream_release(name, version)

      put_upstream_registry_responses(%{{name, version} => {:ok, manifest, tarball}})

      assert {:ok, %PackageVersion{} = package_version} =
               Packages.import_from_upstream(name, version)

      assert :ok = perform_job(Worker, %{"package_version_id" => package_version.id})
      assert {:error, :not_found} = Packages.get_version(name, version)

      assert {:ok, _approved} = Packages.approve_version(name, version)
      assert {:ok, mirrored_manifest} = Packages.get_version(name, version)
      assert mirrored_manifest["name"] == name
      assert mirrored_manifest["version"] == version

      assert {:ok, downloaded} = Packages.get_tarball(name, "approved-mirror-4.5.6.tgz")
      assert downloaded == tarball
    end

    test "accepts upstream tarballs returned as iodata" do
      name = "iodata-mirror"
      version = "1.4.0"
      {:ok, manifest, tarball} = upstream_release(name, version)

      iodata_tarball = [
        binary_part(tarball, 0, 16),
        binary_part(tarball, 16, byte_size(tarball) - 16)
      ]

      put_upstream_registry_responses(%{{name, version} => {:ok, manifest, iodata_tarball}})

      assert {:ok, %PackageVersion{} = package_version} =
               Packages.import_from_upstream(name, version)

      assert package_version.shasum == sha1(tarball)
      assert package_version.integrity == sha512(tarball)
    end

    test "rejects duplicates before fetching upstream" do
      name = "existing-mirror"
      version = "1.0.0"

      assert {:ok, _package_version} =
               Packages.publish(name, publish_payload(name, version))

      assert {:error, :already_exists} = Packages.import_from_upstream(name, version)
    end

    test "returns not found when upstream package is missing" do
      assert {:error, :upstream_not_found} =
               Packages.import_from_upstream("missing-package", "1.0.0")
    end

    test "returns not found when upstream version is missing" do
      put_upstream_registry_responses(%{
        {"missing-version", "9.9.9"} => {:error, :version_not_found}
      })

      assert {:error, :upstream_version_not_found} =
               Packages.import_from_upstream("missing-version", "9.9.9")
    end
  end

  defp storage_root do
    Application.fetch_env!(:reki, Reki.Storage)
    |> Keyword.fetch!(:root)
  end

  defp put_package_approval_steps(steps) do
    previous = Application.get_env(:reki, :package_approval_steps, [])
    Application.put_env(:reki, :package_approval_steps, steps)
    on_exit(fn -> Application.put_env(:reki, :package_approval_steps, previous) end)
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
