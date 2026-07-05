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
