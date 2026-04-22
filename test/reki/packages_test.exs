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
    :ok
  end

  describe "publish/2" do
    test "persists integrity data, hides pending versions from installs, and enqueues approval" do
      name = "widget"
      version = "1.0.0"

      tarball =
        package_tarball(%{"package/package.json" => ~s({"name":"widget","version":"1.0.0"})})

      assert {:ok, %PackageVersion{} = package_version} =
               Packages.publish(name, publish_payload(name, version, tarball))

      assert package_version.validation_status == :pending
      assert package_version.shasum == sha1(tarball)
      assert package_version.integrity == sha512(tarball)
      assert_enqueued(worker: Worker, args: %{"package_version_id" => package_version.id})

      persisted = Repo.get!(PackageVersion, package_version.id)
      assert persisted.shasum == sha1(tarball)
      assert persisted.integrity == sha512(tarball)

      assert {:error, :not_found} = Packages.get_version(name, version)

      assert {:ok, packument} = Packages.get_packument(name)
      assert packument["versions"] == %{}
    end

    test "approved versions are installable and tarballs remain protected by approval" do
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
      assert :ok = perform_job(Worker, %{"package_version_id" => package_version.id})

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

    test "blocking failures mark versions blocked" do
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

      assert :ok = perform_job(Worker, %{"package_version_id" => package_version.id})

      blocked = Repo.get!(PackageVersion, package_version.id)
      assert blocked.validation_status == :blocked
      assert {:error, :not_found} = Packages.get_version(name, version)

      assert %ApprovalRun{status: :failed, steps: [step]} =
               PackageApproval.latest_run(package_version.id)

      assert step.status == :failed
      assert step.exit_code == 7
      assert step.stderr =~ "denied"
    end

    test "an active run prevents duplicate runs" do
      name = "active-widget"
      version = "1.0.0"

      assert {:ok, %PackageVersion{} = package_version} =
               Packages.publish(name, publish_payload(name, version))

      %ApprovalRun{}
      |> ApprovalRun.changeset(%{
        package_version_id: package_version.id,
        status: :running,
        started_at: DateTime.utc_now() |> DateTime.truncate(:second),
        command_set_digest: "manual"
      })
      |> Repo.insert!()

      assert :ok = perform_job(Worker, %{"package_version_id" => package_version.id})

      assert Repo.aggregate(
               from(run in ApprovalRun, where: run.package_version_id == ^package_version.id),
               :count
             ) == 1
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
