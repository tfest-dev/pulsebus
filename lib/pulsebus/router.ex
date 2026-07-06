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

  def topics(server \\ @default_name) do
    GenServer.call(server, :topics)
  end

  def import_events(events, server \\ @default_name) do
    GenServer.call(server, {:import_events, events})
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

  def handle_call(:topics, _from, state) do
    {:reply, summarize_topics(state.events), state}
  end

  def handle_call({:import_events, events}, _from, state) when is_list(events) do
    {imported_events, errors} = validate_import_events(events)

    next_state = %{
      state
      | events: bounded_import(imported_events, state.events, state.buffer_limit)
    }

    summary = %{
      imported: length(imported_events),
      failed: length(errors),
      errors: errors
    }

    {:reply, {:ok, summary}, next_state}
  end

  def handle_call({:import_events, _events}, _from, state) do
    {:reply, {:error, :invalid_events}, state}
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

  defp topic_matches?("*", _topic), do: true

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

  defp bounded_import(imported_events, events, limit) do
    imported_events
    |> Enum.reduce(events, fn event, acc -> bounded_prepend(event, acc, limit) end)
  end

  defp validate_import_events(events) do
    events
    |> Enum.with_index(1)
    |> Enum.reduce({[], []}, fn {attrs, index}, {imported_events, errors} ->
      case Event.import(attrs) do
        {:ok, event} ->
          {[event | imported_events], errors}

        {:error, reason} ->
          {imported_events, [%{index: index, reason: format_reason(reason)} | errors]}
      end
    end)
    |> then(fn {imported_events, errors} ->
      {Enum.reverse(imported_events), Enum.reverse(errors)}
    end)
  end

  defp summarize_topics(events) do
    {summaries, newest_order} =
      Enum.reduce(events, {%{}, []}, fn event, {summaries, newest_order} ->
        case Map.fetch(summaries, event.topic) do
          {:ok, summary} ->
            next_summary = %{summary | count: summary.count + 1}
            {Map.put(summaries, event.topic, next_summary), newest_order}

          :error ->
            summary = %{topic: event.topic, count: 1, last_seen: event.ts}
            {Map.put(summaries, event.topic, summary), [event.topic | newest_order]}
        end
      end)

    newest_order
    |> Enum.reverse()
    |> Enum.map(&Map.fetch!(summaries, &1))
  end

  defp format_id(next_id) do
    "evt_" <> String.pad_leading(Integer.to_string(next_id), 6, "0")
  end

  defp format_reason({:missing_required_field, field}), do: "missing_required_field:#{field}"
  defp format_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp format_reason(reason), do: inspect(reason)
end
