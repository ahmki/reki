defmodule Reki.Storage do
  def put(key, file) do
    path = storage_path(key)

    path
    |> Path.dirname()
    |> File.mkdir_p!()

    case File.write(path, file) do
      :ok -> :ok
      error -> error
    end
  end

  def get(key) do
    File.read(storage_path(key))
  end

  defp storage_path(key) do
    Path.join(root(), key)
  end

  defp root do
    :reki
    |> Application.fetch_env!(__MODULE__)
    |> Keyword.fetch!(:root)
  end
end
