defmodule Reki.PackageApproval.Worker do
  use Oban.Worker, queue: :package_approval, max_attempts: 5

  alias Reki.PackageApproval

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"package_version_id" => package_version_id}}) do
    case PackageApproval.run(package_version_id) do
      {:ok, _status} ->
        :ok

      {:discard, _reason} ->
        :discard

      {:error, reason} ->
        raise "package approval failed unexpectedly: #{inspect(reason)}"
    end
  end
end
