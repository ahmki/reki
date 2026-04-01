defmodule RekiWeb.PageController do
  use RekiWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
