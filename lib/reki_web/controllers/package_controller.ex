defmodule RekiWeb.PackageController do
  use RekiWeb, :controller

  alias Reki.Packages

  def ping(conn, _params) do
    conn
    |> json(%{})
  end

  def show(conn, %{"name" => name}) do
    case Packages.get_packument(URI.decode(name)) do
      {:ok, packument} ->
        conn
        |> json(packument)

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Not found: #{name}"})
    end
  end

  def show_version(conn, %{"name" => name, "version" => version}) do
    case Packages.get_version(URI.decode(name), version) do
      {:ok, manifest} ->
        conn
        |> json(manifest)

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Not found: #{name}@#{version}"})
    end
  end

  def download_tarball(conn, %{"name" => name, "filename" => filename}) do
    key = "#{URI.decode(name)}/-/#{filename}"

    case Reki.Storage.get(key) do
      {:ok, data} ->
        conn
        |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
        |> send_resp(200, data)

      {:error, _} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Not found: #{filename}"})
    end
  end

  def publish(conn, %{"name" => name}) do
    case Packages.publish(URI.decode(name), conn.body_params) do
      {:ok, version} ->
        conn
        |> put_status(:created)
        |> json(%{ok: true, id: "#{name}@#{version.version}"})

      {:error, :invalid_payload} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Invalid publish payload"})

      {:error, %Ecto.Changeset{} = cs} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: format_errors(cs)})

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: inspect(reason)})
    end
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
