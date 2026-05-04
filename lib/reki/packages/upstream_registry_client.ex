defmodule Reki.Packages.UpstreamRegistryClient do
  @callback fetch_release(String.t(), String.t()) ::
              {:ok, map(), binary()}
              | {:error,
                 :not_found | :version_not_found | :tarball_not_found | :invalid_payload | term()}
end
