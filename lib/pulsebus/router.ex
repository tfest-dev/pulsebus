defmodule Pulsebus.Router do
  @moduledoc """
  GenServer event router with a bounded in-memory recent event buffer.
  """

  use GenServer

  alias Pulsebus.Event

  @default_name __MODULE__
  @default_buffer_limit 100

  defstruct buffer_limit: @default_buffer_limit,
            events: [],
            next_id: 1,
            subscribers: %{}

  @type server :: GenServer.server()

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, @default_name)
    start_opts = if is_nil(name), do: [], else: [name: name]

    GenServer.start_link(__MODULE__, opts, start_opts)
  end

  def emit_event(attrs, server \\ @default_name) do
    GenServer.call(server, {:emit_event, attrs})
  end

  def recent_events(server \\ @default_name) do
    GenServer.call(server, :recent_events)
  end

  def subscribe(pattern, pid \\ self(), server \\ @default_name) do
    GenServer.call(server, {:subscribe, pattern, pid})
  end

  @impl true
  def init(opts) do
    buffer_limit = Keyword.get(opts, :buffer_limit, @default_buffer_limit)
    {:ok, %__MODULE__{buffer_limit: buffer_limit}}
  end

  @impl true
  def handle_call({:emit_event, attrs}, _from, state) do
    id = format_id(state.next_id)
    ts = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

    case Event.build(attrs, id, ts) do
      {:ok, event} ->
        notify_subscribers(state.subscribers, event)

        next_state = %{
          state
          | events: bounded_prepend(event, state.events, state.buffer_limit),
            next_id: state.next_id + 1
        }

        {:reply, {:ok, event}, next_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:recent_events, _from, state) do
    {:reply, state.events, state}
  end

  def handle_call({:subscribe, pattern, pid}, _from, state) do
    cond do
      not valid_pattern?(pattern) ->
        {:reply, {:error, :invalid_pattern}, state}

      not is_pid(pid) or not Process.alive?(pid) ->
        {:reply, {:error, :dead_subscriber}, state}

      true ->
        ref = Process.monitor(pid)

        next_state = %{
          state
          | subscribers: Map.put(state.subscribers, ref, {pattern, pid})
        }

        {:reply, :ok, next_state}
    end
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    {_subscriber, subscribers} = Map.pop(state.subscribers, ref)

    {:noreply, %{state | subscribers: subscribers}}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp notify_subscribers(subscribers, event) do
    Enum.each(subscribers, fn {_ref, {pattern, pid}} ->
      if topic_matches?(pattern, event.topic) do
        send(pid, {:pulsebus_event, event})
      end
    end)
  end

  defp topic_matches?(pattern, topic) do
    if String.ends_with?(pattern, ".*") do
      prefix = String.trim_trailing(pattern, "*")
      String.starts_with?(topic, prefix)
    else
      pattern == topic
    end
  end

  defp valid_pattern?(pattern) when is_binary(pattern), do: byte_size(pattern) > 0
  defp valid_pattern?(_pattern), do: false

  defp bounded_prepend(event, events, limit) do
    [event | events] |> Enum.take(limit)
  end

  defp format_id(next_id) do
    "evt_" <> String.pad_leading(Integer.to_string(next_id), 6, "0")
  end
end
