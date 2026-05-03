defmodule RekiWeb.HomeLiveTest do
  use RekiWeb.ConnCase

  import Phoenix.LiveViewTest
  import Reki.PackagesFixtures

  alias Reki.PackageApproval
  alias Reki.Packages
  alias Reki.Repo

  test "shows an empty state when no packages exist", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

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
end
