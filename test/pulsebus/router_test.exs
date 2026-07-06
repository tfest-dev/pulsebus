defmodule Pulsebus.RouterTest do
  use ExUnit.Case, async: true

  alias Pulsebus.Event
  alias Pulsebus.Router

  defp start_router(opts \\ []) do
    start_supervised!({Router, Keyword.put_new(opts, :name, nil)})
  end

  test "valid event emission stores generated event fields" do
    router = start_router()

    assert {:ok, %Event{} = event} =
             Router.emit_event(%{topic: "repo.tests.passed", source: "repo"}, router)

    assert event.id == "evt_000001"
    assert event.topic == "repo.tests.passed"
    assert event.source == "repo"
    assert event.payload == %{}
    assert is_binary(event.ts)
    assert {:ok, _datetime, 0} = DateTime.from_iso8601(event.ts)
    assert Router.recent_events(router) == [event]
  end

  test "invalid missing topic" do
    router = start_router()

    assert Router.emit_event(%{source: "repo"}, router) ==
             {:error, {:missing_required_field, :topic}}
  end

  test "invalid missing source" do
    router = start_router()

    assert Router.emit_event(%{topic: "repo.tests.passed"}, router) ==
             {:error, {:missing_required_field, :source}}
  end

  test "invalid non-map payload" do
    router = start_router()

    assert Router.emit_event(
             %{topic: "repo.tests.passed", source: "repo", payload: "bad"},
             router
           ) ==
             {:error, :invalid_payload}
  end

  test "generated ids increment correctly" do
    router = start_router()

    assert {:ok, first} = Router.emit_event(%{topic: "repo.one", source: "repo"}, router)
    assert {:ok, second} = Router.emit_event(%{topic: "repo.two", source: "repo"}, router)

    assert first.id == "evt_000001"
    assert second.id == "evt_000002"
  end

  test "recent buffer returns newest first" do
    router = start_router()

    assert {:ok, first} = Router.emit_event(%{topic: "repo.one", source: "repo"}, router)
    assert {:ok, second} = Router.emit_event(%{topic: "repo.two", source: "repo"}, router)

    assert Router.recent_events(router) == [second, first]
  end

  test "recent buffer honours configured bound" do
    router = start_router(buffer_limit: 2)

    assert {:ok, _first} = Router.emit_event(%{topic: "repo.one", source: "repo"}, router)
    assert {:ok, second} = Router.emit_event(%{topic: "repo.two", source: "repo"}, router)
    assert {:ok, third} = Router.emit_event(%{topic: "repo.three", source: "repo"}, router)

    assert Router.recent_events(router) == [third, second]
  end

  test "topics returns empty list when no events exist" do
    router = start_router()

    assert Router.topics(router) == []
  end

  test "multiple events for the same topic increment topic count" do
    router = start_router()

    assert {:ok, first} = Router.emit_event(%{topic: "repo.tests.failed", source: "repo"}, router)

    assert {:ok, second} =
             Router.emit_event(%{topic: "repo.tests.failed", source: "repo"}, router)

    assert Router.topics(router) == [
             %{topic: "repo.tests.failed", count: 2, last_seen: second.ts}
           ]

    assert first.topic == second.topic
  end

  test "multiple topics are sorted by most recent activity first" do
    router = start_router()

    assert {:ok, _first} =
             Router.emit_event(%{topic: "repo.tests.failed", source: "repo"}, router)

    assert {:ok, second} =
             Router.emit_event(%{topic: "codex.run.finished", source: "codex"}, router)

    assert {:ok, third} = Router.emit_event(%{topic: "repo.tests.failed", source: "repo"}, router)

    assert Router.topics(router) == [
             %{topic: "repo.tests.failed", count: 2, last_seen: third.ts},
             %{topic: "codex.run.finished", count: 1, last_seen: second.ts}
           ]
  end

  test "topic summary is based only on retained recent buffer contents" do
    router = start_router(buffer_limit: 2)

    assert {:ok, _first} = Router.emit_event(%{topic: "repo.old", source: "repo"}, router)
    assert {:ok, second} = Router.emit_event(%{topic: "repo.kept", source: "repo"}, router)
    assert {:ok, third} = Router.emit_event(%{topic: "repo.kept", source: "repo"}, router)

    assert Router.recent_events(router) == [third, second]

    assert Router.topics(router) == [
             %{topic: "repo.kept", count: 2, last_seen: third.ts}
           ]
  end

  test "valid imported events are added to recent buffer preserving id and timestamp" do
    router = start_router()

    event = %{
      "id" => "evt_logged_001",
      "topic" => "repo.tests.failed",
      "source" => "file",
      "ts" => "2026-07-01T09:30:00Z",
      "payload" => %{"cmd" => "mix test"}
    }

    assert {:ok, %{imported: 1, failed: 0, errors: []}} = Router.import_events([event], router)

    assert [imported] = Router.recent_events(router)
    assert imported.id == "evt_logged_001"
    assert imported.ts == "2026-07-01T09:30:00Z"
    assert imported.payload == %{"cmd" => "mix test"}
  end

  test "imported events do not increment normal emit IDs" do
    router = start_router()

    assert {:ok, %{imported: 1}} =
             Router.import_events(
               [
                 %{
                   "id" => "evt_logged_999",
                   "topic" => "repo.imported",
                   "source" => "file",
                   "ts" => "2026-07-01T09:30:00Z",
                   "payload" => %{}
                 }
               ],
               router
             )

    assert {:ok, event} = Router.emit_event(%{topic: "repo.emitted", source: "repo"}, router)

    assert event.id == "evt_000001"
  end

  test "imported events affect topic summaries" do
    router = start_router()

    assert {:ok, %{imported: 3, failed: 0}} =
             Router.import_events(
               [
                 %{
                   "id" => "evt_logged_001",
                   "topic" => "repo.tests.failed",
                   "source" => "file",
                   "ts" => "2026-07-01T09:30:00Z",
                   "payload" => %{}
                 },
                 %{
                   "id" => "evt_logged_002",
                   "topic" => "codex.run.finished",
                   "source" => "file",
                   "ts" => "2026-07-01T09:31:00Z",
                   "payload" => %{}
                 },
                 %{
                   "id" => "evt_logged_003",
                   "topic" => "repo.tests.failed",
                   "source" => "file",
                   "ts" => "2026-07-01T09:32:00Z",
                   "payload" => %{}
                 }
               ],
               router
             )

    assert Router.topics(router) == [
             %{topic: "repo.tests.failed", count: 2, last_seen: "2026-07-01T09:32:00Z"},
             %{topic: "codex.run.finished", count: 1, last_seen: "2026-07-01T09:31:00Z"}
           ]
  end

  test "mixed valid and invalid import returns clear summary" do
    router = start_router()

    assert {:ok,
            %{
              imported: 1,
              failed: 1,
              errors: [%{index: 2, reason: "missing_required_field:id"}]
            }} =
             Router.import_events(
               [
                 %{
                   "id" => "evt_logged_001",
                   "topic" => "repo.tests.failed",
                   "source" => "file",
                   "ts" => "2026-07-01T09:30:00Z",
                   "payload" => %{}
                 },
                 %{
                   "topic" => "repo.tests.failed",
                   "source" => "file",
                   "ts" => "2026-07-01T09:31:00Z",
                   "payload" => %{}
                 }
               ],
               router
             )

    assert length(Router.recent_events(router)) == 1
  end

  test "recent buffer bound still applies after import" do
    router = start_router(buffer_limit: 2)

    assert {:ok, %{imported: 3, failed: 0}} =
             Router.import_events(
               [
                 %{
                   "id" => "evt_logged_001",
                   "topic" => "repo.one",
                   "source" => "file",
                   "ts" => "2026-07-01T09:30:00Z",
                   "payload" => %{}
                 },
                 %{
                   "id" => "evt_logged_002",
                   "topic" => "repo.two",
                   "source" => "file",
                   "ts" => "2026-07-01T09:31:00Z",
                   "payload" => %{}
                 },
                 %{
                   "id" => "evt_logged_003",
                   "topic" => "repo.three",
                   "source" => "file",
                   "ts" => "2026-07-01T09:32:00Z",
                   "payload" => %{}
                 }
               ],
               router
             )

    assert Enum.map(Router.recent_events(router), & &1.id) == ["evt_logged_003", "evt_logged_002"]
  end

  test "imported events do not notify subscribers" do
    router = start_router()

    assert :ok = Router.subscribe("*", self(), router)

    assert {:ok, %{imported: 1}} =
             Router.import_events(
               [
                 %{
                   "id" => "evt_logged_001",
                   "topic" => "repo.tests.failed",
                   "source" => "file",
                   "ts" => "2026-07-01T09:30:00Z",
                   "payload" => %{}
                 }
               ],
               router
             )

    refute_receive {:pulsebus_event, _event}, 50
  end

  test "exact topic subscriber receives matching event" do
    router = start_router()

    assert :ok = Router.subscribe("repo.tests.failed", self(), router)
    assert {:ok, event} = Router.emit_event(%{topic: "repo.tests.failed", source: "repo"}, router)

    assert_receive {:pulsebus_event, ^event}
  end

  test "exact topic subscriber does not receive non-matching event" do
    router = start_router()

    assert :ok = Router.subscribe("repo.tests.failed", self(), router)

    assert {:ok, _event} =
             Router.emit_event(%{topic: "repo.tests.passed", source: "repo"}, router)

    refute_receive {:pulsebus_event, _event}, 50
  end

  test "prefix wildcard subscriber receives matching event" do
    router = start_router()

    assert :ok = Router.subscribe("repo.*", self(), router)
    assert {:ok, event} = Router.emit_event(%{topic: "repo.tests.failed", source: "repo"}, router)

    assert_receive {:pulsebus_event, ^event}
  end

  test "prefix wildcard subscriber does not receive non-matching event" do
    router = start_router()

    assert :ok = Router.subscribe("codex.run.*", self(), router)

    assert {:ok, _event} =
             Router.emit_event(%{topic: "repo.tests.failed", source: "repo"}, router)

    refute_receive {:pulsebus_event, _event}, 50
  end

  test "all-events wildcard subscriber receives any topic" do
    router = start_router()

    assert :ok = Router.subscribe("*", self(), router)
    assert {:ok, event} = Router.emit_event(%{topic: "repo.tests.failed", source: "repo"}, router)

    assert_receive {:pulsebus_event, ^event}
  end

  test "dead subscriber does not crash router" do
    router = start_router()

    subscriber =
      spawn(fn ->
        receive do
          :stop -> :ok
        end
      end)

    assert :ok = Router.subscribe("repo.*", subscriber, router)

    send(subscriber, :stop)
    ref = Process.monitor(subscriber)
    assert_receive {:DOWN, ^ref, :process, ^subscriber, _reason}

    assert {:ok, event} = Router.emit_event(%{topic: "repo.tests.failed", source: "repo"}, router)
    assert Process.alive?(router)
    assert Router.recent_events(router) == [event]
  end
end
