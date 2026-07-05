defmodule Pulsebus.Subscribers.DesktopNotifyTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Pulsebus.Event
  alias Pulsebus.Router
  alias Pulsebus.Subscribers.DesktopNotify

  defp start_router(opts \\ []) do
    start_supervised!({Router, Keyword.put_new(opts, :name, nil)})
  end

  defp event(attrs \\ %{}) do
    attrs =
      Map.merge(
        %{
          id: "evt_000001",
          topic: "repo.tests.failed",
          source: "repo",
          ts: "2026-07-01T09:30:00Z",
          payload: %{}
        },
        attrs
      )

    struct!(Event, attrs)
  end

  test "formats title and body for an event" do
    assert DesktopNotify.format_notification(event()) ==
             {"Pulsebus: repo.tests.failed", "source=repo id=evt_000001"}
  end

  test "builds command arguments safely" do
    args =
      DesktopNotify.command_args(
        event(%{
          topic: "repo.tests.failed; rm -rf /",
          payload: %{"large" => String.duplicate("x", 1_000)}
        })
      )

    assert args == ["Pulsebus: repo.tests.failed; rm -rf /", "source=repo id=evt_000001"]
  end

  test "configured patterns are used" do
    config = Application.get_env(:pulsebus, :desktop_notify)

    assert config[:patterns] == [
             "repo.tests.failed",
             "codex.run.finished",
             "website.deploy.finished"
           ]
  end

  test "disabled notifier is not supervised by default" do
    children = Supervisor.which_children(Pulsebus.Supervisor)

    refute Enum.any?(children, fn {id, _pid, _type, _modules} ->
             id == DesktopNotify
           end)
  end

  test "matching event triggers notification command" do
    router = start_router()
    parent = self()

    runner = fn command, args, opts ->
      send(parent, {:notify_command, command, args, opts})
      {"", 0}
    end

    start_supervised!(
      {DesktopNotify,
       command: "notify-send", patterns: ["repo.tests.failed"], router: router, runner: runner}
    )

    assert {:ok, event} = Router.emit_event(%{topic: "repo.tests.failed", source: "repo"}, router)

    assert_receive {:notify_command, "notify-send", args, [stderr_to_stdout: true]}
    assert args == DesktopNotify.command_args(event)
  end

  test "non-matching event does not trigger notification command" do
    router = start_router()
    parent = self()

    runner = fn command, args, opts ->
      send(parent, {:notify_command, command, args, opts})
      {"", 0}
    end

    start_supervised!(
      {DesktopNotify,
       command: "notify-send", patterns: ["repo.tests.failed"], router: router, runner: runner}
    )

    assert {:ok, _event} =
             Router.emit_event(%{topic: "repo.tests.passed", source: "repo"}, router)

    refute_receive {:notify_command, _command, _args, _opts}, 50
  end

  test "command failure is handled without crashing the notifier" do
    router = start_router()

    runner = fn _command, _args, _opts ->
      {"failed", 1}
    end

    notifier =
      start_supervised!(
        {DesktopNotify,
         command: "notify-send", patterns: ["repo.tests.failed"], router: router, runner: runner}
      )

    log =
      capture_log(fn ->
        assert {:ok, _event} =
                 Router.emit_event(%{topic: "repo.tests.failed", source: "repo"}, router)

        Process.sleep(20)

        assert Process.alive?(notifier)
        assert Process.alive?(router)
      end)

    assert log =~ "desktop notification command failed"
  end
end
