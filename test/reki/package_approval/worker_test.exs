defmodule Reki.PackageApproval.WorkerTest do
  use Reki.DataCase
  use Oban.Testing, repo: Reki.Repo

  import Reki.PackagesFixtures

  alias Reki.PackageApproval
  alias Reki.PackageApproval.ApprovalRun
  alias Reki.PackageApproval.Worker
  alias Reki.Packages
  alias Reki.Packages.PackageVersion
  alias Reki.Repo

  setup do
    File.rm_rf!(storage_root())
    put_package_approval_steps([])
    :ok
  end

  test "unexpected executor errors mark the run errored and keep the version pending" do
    put_package_approval_steps([
      %{
        name: "bad-working-dir",
        command: "elixir",
        args: ["-e", "IO.write(\"never\")"],
        timeout: 5_000,
        blocking: true,
        working_dir: "../escape"
      }
    ])

    assert {:ok, %PackageVersion{} = package_version} =
             Packages.publish("executor-error", publish_payload("executor-error", "1.0.0"))

    assert {:ok, _job} = PackageApproval.request(package_version)

    assert_raise RuntimeError, ~r/package approval failed unexpectedly/, fn ->
      perform_job(Worker, %{"package_version_id" => package_version.id})
    end

    pending_version = Repo.get!(PackageVersion, package_version.id)
    assert pending_version.validation_status == :pending

    run = PackageApproval.latest_run(package_version.id)
    assert run.status == :errored
    assert Repo.aggregate(ApprovalRun, :count) == 1
    assert Enum.at(run.steps, 0).status == :errored
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
end
