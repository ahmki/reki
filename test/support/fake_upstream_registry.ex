defmodule Reki.TestUpstreamRegistry do
  @behaviour Reki.Packages.UpstreamRegistryClient

  def fetch_release(name, version) do
    responses = Application.get_env(:reki, :test_upstream_registry_responses, %{})

    case Map.fetch(responses, {name, version}) do
      {:ok, response} -> response
      :error -> {:error, :not_found}
    end
  end
end
