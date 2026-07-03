defmodule Pulsebus.ConsoleLogger do
  @moduledoc """
  Minimal process subscriber that prints matching Pulsebus events.
  """

  use GenServer

  require Logger

  def start_link(opts) do
    pattern = Keyword.fetch!(opts, :pattern)
    router = Keyword.get(opts, :router, Pulsebus.Router)

    GenServer.start_link(__MODULE__, {pattern, router}, opts[:gen_server_opts] || [])
  end

  @impl true
  def init({pattern, router}) do
    :ok = Pulsebus.Router.subscribe(pattern, self(), router)
    {:ok, %{pattern: pattern}}
  end

  @impl true
  def handle_info({:pulsebus_event, event}, state) do
    Logger.info("[pulsebus] #{event.ts} #{event.topic} from=#{event.source} id=#{event.id}")
    {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}
end
