defmodule RekiWeb.PageControllerTest do
  use RekiWeb.ConnCase

  import Reki.PackagesFixtures

  alias Reki.Packages
  alias Reki.Repo

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    html = html_response(conn, 200)

    assert html =~ "Available packages"
    assert html =~ "No packages published yet"
    assert html =~ "package-empty-state"
  end

  test "GET / shows package availability cards", %{conn: conn} do
    assert {:ok, approved} =
             Packages.publish("@scope/widget", publish_payload("@scope/widget", "1.0.0"))

    Repo.update!(Ecto.Changeset.change(approved, validation_status: :approved))

    conn = get(conn, ~p"/")
    html = html_response(conn, 200)

    assert html =~ "Installable"
    assert html =~ "@scope/widget"
    assert html =~ "Latest installable"
    assert html =~ "1.0.0"
    assert html =~ "package-catalog"
  end
end
