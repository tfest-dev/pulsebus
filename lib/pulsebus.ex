defmodule Pulsebus do
  @moduledoc """
  Public API for the local Pulsebus event router.
  """

  alias Pulsebus.Router

  @doc """
  Emits an event through the default router.
  """
  def emit_event(attrs), do: Router.emit_event(attrs)

  @doc """
  Returns recent events from the default router, newest first.
  """
  def recent_events, do: Router.recent_events()

  @doc """
  Returns topic summaries derived from the default router's recent event buffer.
  """
  def topics, do: Router.topics()

  @doc """
  Subscribes `pid` to events whose topic matches `pattern`.

  Patterns are exact topic strings, prefix wildcards ending in `.*`, or `*`.
  """
  def subscribe(pattern, pid \\ self()), do: Router.subscribe(pattern, pid)
end
