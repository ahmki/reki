defmodule Reki.PackageApproval.ExecutorTest do
  use ExUnit.Case, async: true

  alias Reki.PackageApproval.Executor

  test "captures stdout and stderr separately" do
    package_root = make_package_root()

    result =
      Executor.run(
        %{
          name: "io-check",
          command: "elixir",
          args: ["-e", "IO.write(\"ok\"); IO.write(:stderr, \"warn\")"],
          timeout: 5_000,
          blocking: true,
          working_dir: ".",
          max_output_bytes: 1_024
        },
        package_root
      )

    assert result.status == :passed
    assert result.exit_code == 0
    assert result.stdout == "ok"
    assert result.stderr == "warn"
  end

  test "enforces output truncation" do
    package_root = make_package_root()

    result =
      Executor.run(
        %{
          name: "truncate-check",
          command: "elixir",
          args: ["-e", "IO.write(String.duplicate(\"a\", 64))"],
          timeout: 5_000,
          blocking: true,
          working_dir: ".",
          max_output_bytes: 16
        },
        package_root
      )

    assert result.stdout == String.duplicate("a", 16) <> "\n...[truncated]"
  end

  test "marks timed out commands" do
    package_root = make_package_root()

    result =
      Executor.run(
        %{
          name: "timeout-check",
          command: "elixir",
          args: ["-e", "Process.sleep(500)"],
          timeout: 50,
          blocking: true,
          working_dir: ".",
          max_output_bytes: 1_024
        },
        package_root
      )

    assert result.status == :timed_out
    assert is_nil(result.exit_code)
  end

  test "argv-based execution does not interpret shell metacharacters" do
    package_root = make_package_root()

    marker =
      Path.join(System.tmp_dir!(), "reki-shell-marker-#{System.unique_integer([:positive])}")

    File.rm_rf(marker)

    result =
      Executor.run(
        %{
          name: "shell-check",
          command: "printf",
          args: ["%s", "$(touch #{marker})"],
          timeout: 5_000,
          blocking: true,
          working_dir: ".",
          max_output_bytes: 1_024
        },
        package_root
      )

    assert result.status == :passed
    assert result.stdout == "$(touch #{marker})"
    refute File.exists?(marker)
  end

  defp make_package_root do
    root =
      Path.join(System.tmp_dir!(), "reki-executor-test-#{System.unique_integer([:positive])}")

    File.mkdir_p!(root)
    root
  end
end
