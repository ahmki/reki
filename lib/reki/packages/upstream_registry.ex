defmodule Reki.Packages.UpstreamRegistry do
  @behaviour Reki.Packages.UpstreamRegistryClient

  def fetch_release(name, version) do
    with {:ok, manifest} <- fetch_version_manifest(name, version),
         {:ok, tarball_url} <- fetch_tarball_url(manifest),
         {:ok, tarball} <- fetch_tarball(tarball_url) do
      {:ok, manifest, tarball}
    end
  end

  defp fetch_packument(name) do
    case Req.get(upstream_package_url(name)) do
      {:ok, %{status: 200, body: body}} when is_map(body) -> {:ok, body}
      {:ok, %{status: 200}} -> {:error, :invalid_payload}
      {:ok, %{status: 404}} -> {:error, :not_found}
      {:ok, %{status: status}} -> {:error, {:unexpected_response, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch_version_manifest(name, version) do
    case Req.get(upstream_version_url(name, version)) do
      {:ok, %{status: 200, body: body}} when is_map(body) -> validate_manifest_body(body)
      {:ok, %{status: 200}} -> {:error, :invalid_payload}
      {:ok, %{status: 404}} -> classify_missing_version(name)
      {:ok, %{status: status}} -> {:error, {:unexpected_response, status}}
      {:error, reason} -> {:error, reason}
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
       do: {:ok, manifest}

  defp validate_manifest_body(_body), do: {:error, :invalid_payload}

  defp fetch_tarball_url(manifest) do
    case get_in(manifest, ["dist", "tarball"]) do
      tarball_url when is_binary(tarball_url) and tarball_url != "" -> {:ok, tarball_url}
      _ -> {:error, :invalid_payload}
    end
  end

  defp fetch_tarball(tarball_url) do
    case Req.get(tarball_url, decode_body: false) do
      {:ok, %{status: 200, body: body}} -> normalize_tarball_body(body)
      {:ok, %{status: 404}} -> {:error, :tarball_not_found}
      {:ok, %{status: status}} -> {:error, {:unexpected_response, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize_tarball_body(body) when is_binary(body), do: {:ok, body}

  defp normalize_tarball_body(body) when is_list(body) do
    try do
      {:ok, IO.iodata_to_binary(body)}
    rescue
      _ -> {:error, :invalid_payload}
    end
  end

  defp normalize_tarball_body(_body), do: {:error, :invalid_payload}

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
end
