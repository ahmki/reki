defmodule RekiWeb.PackageLiveTest do
  use RekiWeb.ConnCase
  use Oban.Testing, repo: Reki.Repo

  import Phoenix.LiveViewTest
  import Reki.PackagesFixtures

  alias Reki.PackageApproval
  alias Reki.PackageApproval.Worker
  alias Reki.Packages

  setup do
    put_package_approval_steps([])
    :ok
  end

  test "shows not found for an unknown package", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/packages/missing-package")

    assert has_element?(view, "#package-not-found")
    assert render(view) =~ "missing-package"
  end

  test "shows all versions and latest approval outputs", %{conn: conn} do
    put_package_approval_steps([
      %{
        name: "io-check",
        command: "elixir",
        args: ["-e", "IO.write(\"ok\"); IO.write(:stderr, \"warn\")"],
        timeout: 5_000,
        blocking: true
      }
    ])

    assert {:ok, approved} =
             Packages.publish("history-widget", publish_payload("history-widget", "1.0.0"))

    assert {:ok, _job} = PackageApproval.request(approved)
    assert :ok = perform_job(Worker, %{"package_version_id" => approved.id})

    assert {:ok, _pending} =
             Packages.publish("history-widget", publish_payload("history-widget", "1.1.0"))

    {:ok, view, _html} = live(conn, "/packages/history-widget")

    assert has_element?(view, "#package-versions", "1.0.0")
    assert has_element?(view, "#package-versions", "1.1.0")
    assert render(view) =~ "All package versions"
    assert has_element?(view, "a", "Inspect outputs")
  end

  test "refreshes when the package changes", %{conn: conn} do
    assert {:ok, package_version} =
             Packages.publish(
               "queued-detail-widget",
               publish_payload("queued-detail-widget", "1.0.0")
             )

    {:ok, view, _html} = live(conn, "/packages/queued-detail-widget")

    assert {:ok, _job} = PackageApproval.request(package_version)

    assert has_element?(view, "#package-versions", "Queued")
  end

  defp put_package_approval_steps(steps) do
    previous = Application.get_env(:reki, :package_approval_steps, [])
    Application.put_env(:reki, :package_approval_steps, steps)
    on_exit(fn -> Application.put_env(:reki, :package_approval_steps, previous) end)
  end
end
