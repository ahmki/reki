defmodule Reki.PackageApproval.Executor do
  def run(step, package_root) do
    output_dir = make_output_dir!()
    stdout_path = Path.join(output_dir, "stdout.log")
    stderr_path = Path.join(output_dir, "stderr.log")
    started_at = DateTime.utc_now() |> DateTime.truncate(:second)

    shell_command =
      [
        "exec",
        shell_escape(step.command),
        Enum.map_join(step.args, " ", &shell_escape/1),
        "1>#{shell_escape(stdout_path)}",
        "2>#{shell_escape(stderr_path)}"
      ]
      |> Enum.reject(&(&1 == ""))
      |> Enum.join(" ")

    port =
      Port.open(
        {:spawn_executable, String.to_charlist("/bin/sh")},
        [
          :binary,
          :exit_status,
          :hide,
          {:args, [~c"-c", String.to_charlist(shell_command)]},
          {:cd, String.to_charlist(resolve_working_dir(package_root, step.working_dir))}
        ]
      )

    result =
      receive_result(
        port,
        started_at,
        step.timeout,
        stdout_path,
        stderr_path,
        step.max_output_bytes
      )

    File.rm_rf!(output_dir)
    result
  end

  defp receive_result(port, started_at, timeout, stdout_path, stderr_path, max_output_bytes) do
    receive do
      {^port, {:exit_status, exit_code}} ->
        finished_at = DateTime.utc_now() |> DateTime.truncate(:second)

        %{
          status: if(exit_code == 0, do: :passed, else: :failed),
          exit_code: exit_code,
          stdout: read_output(stdout_path, max_output_bytes),
          stderr: read_output(stderr_path, max_output_bytes),
          started_at: started_at,
          finished_at: finished_at
        }
    after
      timeout ->
        Port.close(port)
        finished_at = DateTime.utc_now() |> DateTime.truncate(:second)

        %{
          status: :timed_out,
          exit_code: nil,
          stdout: read_output(stdout_path, max_output_bytes),
          stderr: read_output(stderr_path, max_output_bytes),
          started_at: started_at,
          finished_at: finished_at
        }
    end
  end

  defp resolve_working_dir(package_root, ".") do
    package_root
  end

  defp resolve_working_dir(package_root, relative_path) do
    expanded = Path.expand(relative_path, package_root)
    package_root_prefix = package_root <> "/"

    if expanded == package_root or String.starts_with?(expanded, package_root_prefix) do
      expanded
    else
      raise ArgumentError, "package approval working_dir escapes package root"
    end
  end

  defp read_output(path, max_output_bytes) do
    case File.read(path) do
      {:ok, content} when byte_size(content) <= max_output_bytes ->
        content

      {:ok, content} ->
        binary_part(content, 0, max_output_bytes) <> "\n...[truncated]"

      {:error, :enoent} ->
        ""
    end
  end

  defp make_output_dir! do
    dir =
      Path.join(System.tmp_dir!(), "reki-approval-output-#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)
    dir
  end

  defp shell_escape(value) do
    value
    |> String.replace("'", "'\"'\"'")
    |> then(&"'#{&1}'")
  end
end
