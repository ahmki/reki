defmodule RekiWeb.PackageVersionLiveTest do
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

  test "shows not found for an unknown version", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/packages/missing-package/versions/1.0.0")

    assert has_element?(view, "#package-version-not-found")
    assert render(view) =~ "1.0.0"
  end

  test "shows approval outputs on the dedicated version page", %{conn: conn} do
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

    {:ok, view, _html} = live(conn, "/packages/history-widget/versions/1.0.0")

    assert has_element?(view, "#approval-steps", "io-check")
    assert render(view) =~ "ok"
    assert render(view) =~ "warn"
  end

  test "can initiate approval from the version page", %{conn: conn} do
    assert {:ok, package_version} =
             Packages.publish("approval-widget", publish_payload("approval-widget", "1.0.0"))

    {:ok, view, _html} = live(conn, "/packages/approval-widget/versions/1.0.0")

    assert has_element?(view, "#request-approval", "Run approval")

    view
    |> element("#request-approval")
    |> render_click()

    assert has_element?(view, "#request-approval", "Approval running")
    assert render(view) =~ "Approval queued for 1.0.0."
    assert PackageApproval.latest_run(package_version.id).status == :queued
  end

  test "can manually approve a version after inspecting results", %{conn: conn} do
    put_package_approval_steps([
      %{
        name: "pass-check",
        command: "elixir",
        args: ["-e", "IO.write(\"ok\")"],
        timeout: 5_000,
        blocking: true
      }
    ])

    assert {:ok, package_version} =
             Packages.publish(
               "manual-approve-widget",
               publish_payload("manual-approve-widget", "1.0.0")
             )

    assert {:ok, _job} = PackageApproval.request(package_version)
    assert :ok = perform_job(Worker, %{"package_version_id" => package_version.id})

    {:ok, view, _html} = live(conn, "/packages/manual-approve-widget/versions/1.0.0")

    view
    |> element("#approve-version")
    |> render_click()

    assert render(view) =~ "1.0.0 approved."
    assert has_element?(view, "span", "Approved")
  end

  test "can manually block a version after inspecting results", %{conn: conn} do
    put_package_approval_steps([
      %{
        name: "fail-check",
        command: "elixir",
        args: ["-e", "IO.write(:stderr, \"nope\"); System.halt(7)"],
        timeout: 5_000,
        blocking: true
      }
    ])

    assert {:ok, package_version} =
             Packages.publish(
               "manual-block-widget",
               publish_payload("manual-block-widget", "1.0.0")
             )

    assert {:ok, _job} = PackageApproval.request(package_version)
    assert :ok = perform_job(Worker, %{"package_version_id" => package_version.id})

    {:ok, view, _html} = live(conn, "/packages/manual-block-widget/versions/1.0.0")

    view
    |> element("#block-version")
    |> render_click()

    assert render(view) =~ "1.0.0 blocked."
    assert has_element?(view, "span", "Blocked")
  end

  defp put_package_approval_steps(steps) do
    previous = Application.get_env(:reki, :package_approval_steps, [])
    Application.put_env(:reki, :package_approval_steps, steps)
    on_exit(fn -> Application.put_env(:reki, :package_approval_steps, previous) end)
  end
end
