defmodule PulsebusTest do
  use ExUnit.Case, async: false

  setup do
    reset_default_router()
    :ok
  end

  test "topics returns empty list when no events exist" do
    assert Pulsebus.topics() == []
  end

  defp reset_default_router do
    :ok = Supervisor.terminate_child(Pulsebus.Supervisor, Pulsebus.Router)

    case Supervisor.restart_child(Pulsebus.Supervisor, Pulsebus.Router) do
      {:ok, _pid} -> :ok
      {:ok, _pid, _info} -> :ok
    end
  end
end
