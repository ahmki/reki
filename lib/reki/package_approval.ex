defmodule Reki.PackageApproval do
  import Ecto.Query

  alias Reki.PackageApproval.{ApprovalRun, Runner, Worker}
  alias Reki.Packages.PackageVersion
  alias Reki.Repo

  def request(%PackageVersion{id: package_version_id}) do
    request(package_version_id)
  end

  def request(package_version_id) when is_binary(package_version_id) do
    %{package_version_id: package_version_id}
    |> Worker.new()
    |> Oban.insert()
  end

  def enqueue(package_version_id) do
    %{package_version_id: package_version_id}
    |> Worker.new()
    |> Oban.insert()
    |> case do
      {:ok, _job} ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  def run(package_version_id) do
    Runner.run(package_version_id)
  end

  def latest_run(package_version_id) do
    Repo.one(
      from run in ApprovalRun,
        where: run.package_version_id == ^package_version_id,
        order_by: [desc: run.inserted_at],
        preload: [
          steps:
            ^from(step in Reki.PackageApproval.ApprovalRunStep, order_by: [asc: step.inserted_at])
        ]
    )
  end

  def steps do
    Application.get_env(:reki, :package_approval_steps, [])
    |> Enum.map(&normalize_step!/1)
  end

  def command_set_digest(steps \\ steps()) do
    steps
    |> Enum.map(
      &Map.take(&1, [:name, :command, :args, :timeout, :blocking, :working_dir, :max_output_bytes])
    )
    |> Jason.encode!()
    |> then(fn encoded -> :crypto.hash(:sha256, encoded) end)
    |> Base.encode16(case: :lower)
  end

  def executor_module do
    Application.get_env(:reki, :package_approval_executor, Reki.PackageApproval.Executor)
  end

  defp normalize_step!(step) when is_list(step) do
    step |> Enum.into(%{}) |> normalize_step!()
  end

  defp normalize_step!(%{} = step) do
    %{
      name: fetch_string!(step, :name),
      command: fetch_string!(step, :command),
      args: fetch_string_list!(step, :args, []),
      timeout: fetch_integer!(step, :timeout, 30_000),
      blocking: fetch_boolean!(step, :blocking, true),
      working_dir: fetch_string!(step, :working_dir, "."),
      max_output_bytes: fetch_integer!(step, :max_output_bytes, 16_384)
    }
  end

  defp fetch_string!(map, key, default \\ nil) do
    value = Map.get(map, key, default)

    if is_binary(value) and value != "" do
      value
    else
      raise ArgumentError, "invalid package approval step #{inspect(key)}: #{inspect(value)}"
    end
  end

  defp fetch_string_list!(map, key, default) do
    value = Map.get(map, key, default)

    if is_list(value) and Enum.all?(value, &is_binary/1) do
      value
    else
      raise ArgumentError, "invalid package approval step #{inspect(key)}: #{inspect(value)}"
    end
  end

  defp fetch_integer!(map, key, default) do
    value = Map.get(map, key, default)

    if is_integer(value) and value > 0 do
      value
    else
      raise ArgumentError, "invalid package approval step #{inspect(key)}: #{inspect(value)}"
    end
  end

  defp fetch_boolean!(map, key, default) do
    value = Map.get(map, key, default)

    if is_boolean(value) do
      value
    else
      raise ArgumentError, "invalid package approval step #{inspect(key)}: #{inspect(value)}"
    end
  end
end
