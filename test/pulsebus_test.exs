defmodule PulsebusTest do
  use ExUnit.Case, async: false

  setup do
    reset_default_router()
    :ok
  end

  test "topics returns empty list when no events exist" do
    assert Pulsebus.topics() == []
  end

  test "import_events imports through public API" do
    assert {:ok, %{imported: 1, failed: 0}} =
             Pulsebus.import_events([
               %{
                 "id" => "evt_logged_001",
                 "topic" => "repo.tests.failed",
                 "source" => "file",
                 "ts" => "2026-07-01T09:30:00Z",
                 "payload" => %{}
               }
             ])

    assert [%{id: "evt_logged_001"}] = Pulsebus.recent_events()
  end

  defp reset_default_router do
    :ok = Supervisor.terminate_child(Pulsebus.Supervisor, Pulsebus.Router)

    case Supervisor.restart_child(Pulsebus.Supervisor, Pulsebus.Router) do
      {:ok, _pid} -> :ok
      {:ok, _pid, _info} -> :ok
    end
  end
end
