defmodule RekiWeb.HomeLiveTest do
  use RekiWeb.ConnCase
  use Oban.Testing, repo: Reki.Repo

  import Phoenix.LiveViewTest
  import Reki.PackagesFixtures

  alias Reki.PackageApproval
  alias Reki.Packages
  alias Reki.Repo

  setup do
    put_package_approval_steps([])
    put_upstream_registry_client(Reki.TestUpstreamRegistry)
    put_upstream_registry_responses(%{})
    :ok
  end

  test "shows an empty state when no packages exist", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#package-import-form")
    assert has_element?(view, "#package-import-name")
    assert has_element?(view, "#package-import-version")
    assert has_element?(view, "#package-empty-state")
    assert has_element?(view, "#package-catalog")
    refute has_element?(view, "#package-catalog article")
  end

  test "shows package availability cards", %{conn: conn} do
    assert {:ok, approved} =
             Packages.publish("@scope/widget", publish_payload("@scope/widget", "1.0.0"))

    Repo.update!(Ecto.Changeset.change(approved, validation_status: :approved))

    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#package-catalog article")
    assert has_element?(view, "#package-catalog", "@scope/widget")
    assert has_element?(view, "#package-catalog", "Installable")
    assert has_element?(view, "#package-catalog", "Latest installable")
    assert render(view) =~ "1.0.0"
  end

  test "refreshes when packages change", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    refute has_element?(view, "#package-catalog", "live-widget")

    assert {:ok, approved} =
             Packages.publish("live-widget", publish_payload("live-widget", "1.0.0"))

    Repo.update!(Ecto.Changeset.change(approved, validation_status: :approved))
    Packages.broadcast_catalog_updated()

    assert has_element?(view, "#package-catalog", "live-widget")
  end

  test "shows queued after approval is requested", %{conn: conn} do
    assert {:ok, package_version} =
             Packages.publish("queued-ui-widget", publish_payload("queued-ui-widget", "1.0.0"))

    {:ok, view, _html} = live(conn, ~p"/")

    assert {:ok, _job} = PackageApproval.request(package_version)

    assert has_element?(view, "#package-catalog", "queued-ui-widget")
    assert has_element?(view, "#package-catalog", "Queued")
  end

  test "links to the dedicated package view", %{conn: conn} do
    assert {:ok, _approved} =
             Packages.publish("@scope/widget", publish_payload("@scope/widget", "1.0.0"))

    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#package-catalog", "@scope/widget")
    assert has_element?(view, "a", "View package")
  end

  test "imports a package from npm and updates the catalog", %{conn: conn} do
    name = "@scope/mirrored-live"
    version = "3.1.4"
    {:ok, manifest, tarball} = upstream_release(name, version)

    put_upstream_registry_responses(%{{name, version} => {:ok, manifest, tarball}})

    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> form("#package-import-form", import: %{"name" => name, "version" => version})
    |> render_submit()

    assert_redirect(view, "/packages/@scope/mirrored-live/versions/3.1.4")
  end

  test "shows an error when upstream import fails", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> form("#package-import-form", import: %{"name" => "missing-package", "version" => "1.0.0"})
    |> render_submit()

    assert render(view) =~ "Upstream package not found: missing-package."
    assert has_element?(view, "#package-empty-state")
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
end
