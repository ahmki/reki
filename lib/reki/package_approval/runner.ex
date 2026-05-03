defmodule Reki.PackageApproval.Runner do
  import Ecto.Query

  alias Reki.PackageApproval
  alias Reki.PackageApproval.{ApprovalRun, ApprovalRunStep}
  alias Reki.Packages
  alias Reki.Packages.PackageVersion
  alias Reki.Repo
  alias Reki.Storage

  def run(package_version_id) do
    case Repo.get(PackageVersion, package_version_id) do
      nil ->
        {:discard, :not_found}

      %PackageVersion{validation_status: status} when status in [:approved, :blocked] ->
        {:ok, :already_decided}

      %PackageVersion{} ->
        do_run(package_version_id)
    end
  end

  defp do_run(package_version_id) do
    steps = PackageApproval.steps()

    case start_run(package_version_id, steps) do
      {:ok, nil} ->
        {:ok, :already_running}

      {:ok, run} ->
        execute_run(run, steps)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp start_run(package_version_id, steps) do
    started_at = DateTime.utc_now() |> DateTime.truncate(:second)
    digest = PackageApproval.command_set_digest(steps)

    Repo.transaction(fn ->
      case active_run(package_version_id) do
        %ApprovalRun{status: :running} ->
          nil

        %ApprovalRun{status: :queued} = run ->
          run
          |> ApprovalRun.changeset(%{
            status: :running,
            started_at: started_at,
            command_set_digest: digest
          })
          |> Repo.update!()

        nil ->
          %ApprovalRun{}
          |> ApprovalRun.changeset(%{
            package_version_id: package_version_id,
            status: :running,
            started_at: started_at,
            command_set_digest: digest
          })
          |> Repo.insert!()
      end
    end)
  end

  defp execute_run(run, steps) do
    with {:ok, package_version} <- fetch_package_version(run.package_version_id),
         {:ok, %{workspace: workspace, package_root: package_root}} <-
           materialize_package(package_version) do
      result =
        try do
          steps
          |> run_steps(run, package_root)
          |> finalize_run(run, package_version.id)
        after
          File.rm_rf(workspace)
        end

      result
    else
      {:error, reason} ->
        mark_run_errored(run, reason)
        {:error, reason}
    end
  end

  defp run_steps(steps, run, package_root) do
    do_run_steps(steps, run, package_root, [])
  end

  defp do_run_steps([], _run, _package_root, persisted_steps) do
    %{steps: persisted_steps, halted_at: nil}
  end

  defp do_run_steps([step | remaining_steps], run, package_root, persisted_steps) do
    persisted_step = execute_step(run.id, step, package_root)
    updated_steps = persisted_steps ++ [persisted_step]

    cond do
      persisted_step.status == :errored ->
        skipped = Enum.map(remaining_steps, &persist_skipped_step(run.id, &1))
        %{steps: updated_steps ++ skipped, halted_at: :errored}

      persisted_step.status in [:failed, :timed_out] and step.blocking ->
        skipped = Enum.map(remaining_steps, &persist_skipped_step(run.id, &1))
        %{steps: updated_steps ++ skipped, halted_at: persisted_step.status}

      true ->
        do_run_steps(remaining_steps, run, package_root, updated_steps)
    end
  end

  defp execute_step(run_id, step, package_root) do
    result =
      try do
        PackageApproval.executor_module().run(step, package_root)
      rescue
        error ->
          error_result(Exception.message(error))
      catch
        kind, reason ->
          error_result(Exception.format_banner(kind, reason))
      end

    persist_step(run_id, step, result)
  end

  defp finalize_run(%{steps: steps, halted_at: :errored}, run, _package_version_id) do
    summary = build_summary(steps)

    run
    |> ApprovalRun.changeset(%{
      status: :errored,
      finished_at: DateTime.utc_now() |> DateTime.truncate(:second),
      summary: summary
    })
    |> Repo.update!()

    {:error, :approval_step_errored}
  end

  defp finalize_run(%{steps: steps}, run, package_version_id) do
    summary = build_summary(steps)
    blocking_failure? = Enum.any?(steps, &blocking_failure?/1)

    run_status = if blocking_failure?, do: :failed, else: :passed
    finished_at = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.transaction(fn ->
      run
      |> ApprovalRun.changeset(%{
        status: run_status,
        finished_at: finished_at,
        summary: summary
      })
      |> Repo.update!()

      from(version in PackageVersion, where: version.id == ^package_version_id)
      |> Repo.update_all(
        set: [
          validation_results: summary,
          updated_at: finished_at
        ]
      )
    end)

    Packages.broadcast_catalog_updated()

    {:ok, run_status}
  end

  defp mark_run_errored(run, reason) do
    run
    |> ApprovalRun.changeset(%{
      status: :errored,
      finished_at: DateTime.utc_now() |> DateTime.truncate(:second),
      summary: %{"error" => inspect(reason)}
    })
    |> Repo.update()
  end

  defp fetch_package_version(package_version_id) do
    case Repo.one(
           from version in PackageVersion,
             where: version.id == ^package_version_id,
             preload: :package
         ) do
      nil -> {:error, :package_version_not_found}
      version -> {:ok, version}
    end
  end

  defp materialize_package(package_version) do
    workspace =
      Path.join(System.tmp_dir!(), "reki-package-approval-#{System.unique_integer([:positive])}")

    File.mkdir_p!(workspace)

    tarball_key =
      "#{package_version.package.name}/-/#{package_slug(package_version.package.name)}-#{package_version.version}.tgz"

    try do
      with {:ok, tarball} <- Storage.get(tarball_key),
           {:ok, package_root} <- extract_tarball(tarball, workspace) do
        {:ok, %{workspace: workspace, package_root: package_root}}
      else
        {:error, reason} ->
          File.rm_rf!(workspace)
          {:error, reason}
      end
    rescue
      error ->
        File.rm_rf!(workspace)
        {:error, {:materialize_failed, Exception.message(error)}}
    catch
      kind, reason ->
        File.rm_rf!(workspace)
        {:error, {:materialize_failed, Exception.format_banner(kind, reason)}}
    end
  end

  defp extract_tarball(tarball, workspace) do
    with {:ok, entries} <- :erl_tar.extract({:binary, tarball}, [:compressed, :memory]) do
      top_levels =
        Enum.reduce_while(entries, MapSet.new(), fn entry, acc ->
          case entry do
            {path, contents} when is_list(path) and is_binary(contents) ->
              relative_path = sanitize_path(path)
              full_path = Path.join(workspace, relative_path)
              File.mkdir_p!(Path.dirname(full_path))
              File.write!(full_path, contents)
              top_level = relative_path |> String.split("/", parts: 2) |> hd()
              {:cont, MapSet.put(acc, top_level)}

            _ ->
              {:halt, {:error, :unsupported_tar_entry}}
          end
        end)

      case top_levels do
        {:error, reason} ->
          {:error, reason}

        top_levels ->
          package_root =
            case MapSet.to_list(top_levels) do
              [single_root] -> Path.join(workspace, single_root)
              _ -> workspace
            end

          {:ok, package_root}
      end
    end
  end

  defp sanitize_path(path) do
    path
    |> List.to_string()
    |> then(fn relative_path ->
      normalized = Path.expand(relative_path, "/")
      expected = "/" <> relative_path

      cond do
        relative_path == "" ->
          raise ArgumentError, "tar entry cannot be empty"

        Path.type(relative_path) == :absolute ->
          raise ArgumentError, "tar entry cannot be absolute"

        normalized != expected ->
          raise ArgumentError, "tar entry escapes root"

        true ->
          relative_path
      end
    end)
  end

  defp persist_step(run_id, step, result) do
    %ApprovalRunStep{}
    |> ApprovalRunStep.changeset(%{
      approval_run_id: run_id,
      name: step.name,
      command: %{
        "command" => step.command,
        "args" => step.args,
        "working_dir" => step.working_dir,
        "timeout" => step.timeout,
        "blocking" => step.blocking
      },
      status: result.status,
      exit_code: result.exit_code,
      stdout: result.stdout,
      stderr: result.stderr,
      started_at: result.started_at,
      finished_at: result.finished_at
    })
    |> Repo.insert!()
  end

  defp persist_skipped_step(run_id, step) do
    timestamp = DateTime.utc_now() |> DateTime.truncate(:second)

    persist_step(run_id, step, %{
      status: :skipped,
      exit_code: nil,
      stdout: "",
      stderr: "",
      started_at: timestamp,
      finished_at: timestamp
    })
  end

  defp build_summary(steps) do
    %{
      "step_count" => length(steps),
      "statuses" => Enum.frequencies_by(steps, &Atom.to_string(&1.status)),
      "steps" =>
        Enum.map(steps, fn step ->
          %{
            "name" => step.name,
            "status" => Atom.to_string(step.status),
            "exit_code" => step.exit_code
          }
        end)
    }
  end

  defp error_result(stderr) do
    timestamp = DateTime.utc_now() |> DateTime.truncate(:second)

    %{
      status: :errored,
      exit_code: nil,
      stdout: "",
      stderr: stderr,
      started_at: timestamp,
      finished_at: timestamp
    }
  end

  defp blocking_failure?(step) do
    get_in(step.command, ["blocking"]) and step.status in [:failed, :timed_out]
  end

  defp active_run(package_version_id) do
    Repo.one(
      from run in ApprovalRun,
        where:
          run.package_version_id == ^package_version_id and run.status in [:queued, :running],
        order_by: [desc: run.inserted_at],
        limit: 1
    )
  end

  defp package_slug(name) do
    name
    |> String.split("/")
    |> List.last()
  end
end
