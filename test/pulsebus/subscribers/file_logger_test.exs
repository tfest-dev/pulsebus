defmodule Pulsebus.Subscribers.FileLoggerTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Pulsebus.Router
  alias Pulsebus.Subscribers.FileLogger

  defp start_router(opts \\ []) do
    start_supervised!({Router, Keyword.put_new(opts, :name, nil)})
  end

  defp temp_path(context) do
    dir = Path.join(System.tmp_dir!(), "pulsebus_file_logger_#{context.test}")
    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)

    Path.join(dir, "events.jsonl")
  end

  defp read_lines(path) do
    path
    |> File.read!()
    |> String.split("\n", trim: true)
  end

  defp wait_for_lines(path, count, attempts \\ 20)

  defp wait_for_lines(path, count, attempts) when attempts > 0 do
    if File.exists?(path) and length(read_lines(path)) >= count do
      read_lines(path)
    else
      Process.sleep(10)
      wait_for_lines(path, count, attempts - 1)
    end
  end

  defp wait_for_lines(path, _count, 0), do: if(File.exists?(path), do: read_lines(path), else: [])

  test "writes a valid emitted event to JSONL", context do
    router = start_router()
    path = temp_path(context)

    start_supervised!({FileLogger, path: path, router: router})

    assert {:ok, event} =
             Router.emit_event(%{topic: "repo.tests.failed", source: "repo"}, router)

    assert [line] = wait_for_lines(path, 1)

    assert Jason.decode!(line) == %{
             "id" => event.id,
             "topic" => "repo.tests.failed",
             "source" => "repo",
             "ts" => event.ts,
             "payload" => %{}
           }
  end

  test "multiple events append multiple lines", context do
    router = start_router()
    path = temp_path(context)

    start_supervised!({FileLogger, path: path, router: router})

    assert {:ok, first} = Router.emit_event(%{topic: "repo.one", source: "repo"}, router)
    assert {:ok, second} = Router.emit_event(%{topic: "repo.two", source: "repo"}, router)

    assert [first_line, second_line] = wait_for_lines(path, 2)
    assert Jason.decode!(first_line)["id"] == first.id
    assert Jason.decode!(second_line)["id"] == second.id
  end

  test "logged events include id topic source ts and payload", context do
    router = start_router()
    path = temp_path(context)

    start_supervised!({FileLogger, path: path, router: router})

    assert {:ok, event} =
             Router.emit_event(
               %{topic: "repo.tests.failed", source: "repo", payload: %{"cmd" => "mix test"}},
               router
             )

    assert [line] = wait_for_lines(path, 1)
    logged = Jason.decode!(line)

    assert logged["id"] == event.id
    assert logged["topic"] == event.topic
    assert logged["source"] == event.source
    assert logged["ts"] == event.ts
    assert logged["payload"] == %{"cmd" => "mix test"}
  end

  test "file logger can subscribe via all-events wildcard", context do
    router = start_router()
    path = temp_path(context)

    start_supervised!({FileLogger, path: path, router: router, patterns: ["*"]})

    assert {:ok, event} =
             Router.emit_event(%{topic: "codex.run.started", source: "codex"}, router)

    assert [line] = wait_for_lines(path, 1)
    assert Jason.decode!(line)["id"] == event.id
  end

  test "disabled file logger config does not create a log file", context do
    path = temp_path(context)
    config = Application.get_env(:pulsebus, :file_logger)

    refute config[:enabled]
    refute File.exists?(path)
  end

  test "file logger write failure does not crash the router" do
    router = start_router()
    missing_dir_path = Path.join(System.tmp_dir!(), "pulsebus_missing_dir/events.jsonl")

    start_supervised!({FileLogger, path: missing_dir_path, router: router})

    log =
      capture_log(fn ->
        assert {:ok, event} =
                 Router.emit_event(%{topic: "repo.tests.failed", source: "repo"}, router)

        Process.sleep(20)

        assert Process.alive?(router)
        assert Router.recent_events(router) == [event]
      end)

    assert log =~ "failed to write event log"
  end
end
