defmodule Reki.Packages.UpstreamRegistry do
  @behaviour Reki.Packages.UpstreamRegistryClient

  require Logger

  def fetch_release(name, version) do
    Logger.debug("upstream fetch_release start name=#{inspect(name)} version=#{inspect(version)}")

    with {:ok, manifest} <- fetch_version_manifest(name, version),
         {:ok, tarball_url} <- fetch_tarball_url(manifest),
         {:ok, tarball} <- fetch_tarball(tarball_url) do
      Logger.debug(
        "upstream fetch_release success name=#{inspect(name)} version=#{inspect(version)} tarball_bytes=#{byte_size(tarball)}"
      )

      {:ok, manifest, tarball}
    else
      {:error, reason} = error ->
        Logger.debug(
          "upstream fetch_release failed name=#{inspect(name)} version=#{inspect(version)} reason=#{inspect(reason)}"
        )

        error
    end
  end

  defp fetch_packument(name) do
    case Req.get(upstream_package_url(name)) do
      {:ok, %{status: 200, body: body}} when is_map(body) ->
        Logger.debug(
          "upstream fetch_packument ok name=#{inspect(name)} keys=#{inspect(Map.keys(body) |> Enum.take(10))}"
        )

        {:ok, body}

      {:ok, %{status: 200, body: body}} ->
        Logger.debug(
          "upstream fetch_packument invalid body name=#{inspect(name)} body_type=#{body_type(body)}"
        )

        {:error, :invalid_payload}

      {:ok, %{status: 404}} ->
        Logger.debug("upstream fetch_packument missing name=#{inspect(name)}")
        {:error, :not_found}

      {:ok, %{status: status, body: body}} ->
        Logger.debug(
          "upstream fetch_packument unexpected name=#{inspect(name)} status=#{status} body_type=#{body_type(body)}"
        )

        {:error, {:unexpected_response, status}}

      {:error, reason} ->
        Logger.debug(
          "upstream fetch_packument error name=#{inspect(name)} reason=#{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  defp fetch_version_manifest(name, version) do
    case Req.get(upstream_version_url(name, version)) do
      {:ok, %{status: 200, body: body}} when is_map(body) ->
        Logger.debug(
          "upstream fetch_version_manifest ok name=#{inspect(name)} version=#{inspect(version)} keys=#{inspect(Map.keys(body) |> Enum.take(10))}"
        )

        validate_manifest_body(body)

      {:ok, %{status: 200, body: body}} ->
        Logger.debug(
          "upstream fetch_version_manifest invalid body name=#{inspect(name)} version=#{inspect(version)} body_type=#{body_type(body)}"
        )

        {:error, :invalid_payload}

      {:ok, %{status: 404}} ->
        Logger.debug(
          "upstream fetch_version_manifest missing name=#{inspect(name)} version=#{inspect(version)}"
        )

        classify_missing_version(name)

      {:ok, %{status: status, body: body}} ->
        Logger.debug(
          "upstream fetch_version_manifest unexpected name=#{inspect(name)} version=#{inspect(version)} status=#{status} body_type=#{body_type(body)}"
        )

        {:error, {:unexpected_response, status}}

      {:error, reason} ->
        Logger.debug(
          "upstream fetch_version_manifest error name=#{inspect(name)} version=#{inspect(version)} reason=#{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  defp classify_missing_version(name) do
    case fetch_packument(name) do
      {:ok, _packument} -> {:error, :version_not_found}
      {:error, :not_found} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_manifest_body(%{"name" => name, "version" => version} = manifest)
       when is_binary(name) and is_binary(version),
       do: log_valid_manifest(manifest)

  defp validate_manifest_body(body) do
    Logger.debug(
      "upstream validate_manifest_body invalid body_type=#{body_type(body)} keys=#{inspect(map_keys(body))}"
    )

    {:error, :invalid_payload}
  end

  defp fetch_tarball_url(manifest) do
    case get_in(manifest, ["dist", "tarball"]) do
      tarball_url when is_binary(tarball_url) and tarball_url != "" ->
        Logger.debug(
          "upstream fetch_tarball_url ok package=#{inspect(manifest["name"])} version=#{inspect(manifest["version"])} tarball_url=#{inspect(tarball_url)}"
        )

        {:ok, tarball_url}

      other ->
        Logger.debug(
          "upstream fetch_tarball_url invalid package=#{inspect(manifest["name"])} version=#{inspect(manifest["version"])} dist=#{inspect(manifest["dist"])} tarball_field=#{inspect(other)}"
        )

        {:error, :invalid_payload}
    end
  end

  defp fetch_tarball(tarball_url) do
    case Req.get(tarball_url, decode_body: false) do
      {:ok, %{status: 200, body: body}} ->
        Logger.debug(
          "upstream fetch_tarball ok url=#{inspect(tarball_url)} body_type=#{body_type(body)} iodata_bytes=#{inspect(iodata_size(body))}"
        )

        normalize_tarball_body(body)

      {:ok, %{status: 404}} ->
        Logger.debug("upstream fetch_tarball missing url=#{inspect(tarball_url)}")
        {:error, :tarball_not_found}

      {:ok, %{status: status, body: body}} ->
        Logger.debug(
          "upstream fetch_tarball unexpected url=#{inspect(tarball_url)} status=#{status} body_type=#{body_type(body)}"
        )

        {:error, {:unexpected_response, status}}

      {:error, reason} ->
        Logger.debug(
          "upstream fetch_tarball error url=#{inspect(tarball_url)} reason=#{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  defp normalize_tarball_body(body) when is_binary(body) do
    Logger.debug("upstream normalize_tarball_body binary bytes=#{byte_size(body)}")
    {:ok, body}
  end

  defp normalize_tarball_body(body) when is_list(body) do
    try do
      binary = IO.iodata_to_binary(body)
      Logger.debug("upstream normalize_tarball_body iodata bytes=#{byte_size(binary)}")
      {:ok, binary}
    rescue
      error ->
        Logger.debug(
          "upstream normalize_tarball_body invalid iodata body_type=#{body_type(body)} error=#{Exception.message(error)}"
        )

        {:error, :invalid_payload}
    end
  end

  defp normalize_tarball_body(body) do
    Logger.debug("upstream normalize_tarball_body invalid body_type=#{body_type(body)}")
    {:error, :invalid_payload}
  end

  defp upstream_package_url(name) do
    "#{registry_url()}/#{URI.encode(name)}"
  end

  defp upstream_version_url(name, version) do
    "#{registry_url()}/#{URI.encode(name)}/#{URI.encode(version)}"
  end

  defp registry_url do
    :reki
    |> Application.get_env(:npm_registry_url, "https://registry.npmjs.org")
    |> String.trim_trailing("/")
  end

  defp log_valid_manifest(manifest) do
    Logger.debug(
      "upstream validate_manifest_body ok name=#{inspect(manifest["name"])} version=#{inspect(manifest["version"])} has_dist=#{is_map(manifest["dist"])} dist_keys=#{inspect(map_keys(manifest["dist"]))}"
    )

    {:ok, manifest}
  end

  defp map_keys(map) when is_map(map), do: Map.keys(map) |> Enum.take(10)
  defp map_keys(_), do: nil

  defp body_type(body) when is_binary(body), do: :binary
  defp body_type(body) when is_list(body), do: :list
  defp body_type(body) when is_map(body), do: :map
  defp body_type(body), do: body |> Kernel.inspect(limit: 5) |> String.slice(0, 120)

  defp iodata_size(body) do
    {:ok, IO.iodata_length(body)}
  rescue
    _ -> :unknown
  end
end
