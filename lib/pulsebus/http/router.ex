defmodule Pulsebus.HTTP.Router do
  @moduledoc """
  Thin local HTTP interface for emitting and reading Pulsebus events.
  """

  use Plug.Router

  plug(:match)
  plug(:dispatch)

  get "/health" do
    send_json(conn, 200, %{status: "ok"})
  end

  post "/events" do
    with :ok <- require_json_content_type(conn),
         {:ok, attrs} <- read_json_map(conn),
         {:ok, event} <- Pulsebus.emit_event(attrs) do
      send_json(conn, 201, event_to_map(event))
    else
      {:error, :unsupported_content_type} ->
        send_json(conn, 415, %{error: "unsupported_content_type"})

      {:error, :invalid_json} ->
        send_json(conn, 400, %{error: "invalid_json"})

      {:error, :invalid_request_body} ->
        send_json(conn, 400, %{error: "invalid_request_body"})

      {:error, reason} ->
        send_json(conn, 400, %{error: "validation_failed", reason: format_reason(reason)})
    end
  end

  post "/events/import" do
    with :ok <- require_json_content_type(conn),
         {:ok, events} <- read_json_array(conn),
         {:ok, summary} <- Pulsebus.import_events(events) do
      send_json(conn, 200, summary)
    else
      {:error, :unsupported_content_type} ->
        send_json(conn, 415, %{error: "unsupported_content_type"})

      {:error, :invalid_json} ->
        send_json(conn, 400, %{error: "invalid_json"})

      {:error, :invalid_request_body} ->
        send_json(conn, 400, %{error: "invalid_request_body"})

      {:error, reason} ->
        send_json(conn, 400, %{error: "import_failed", reason: format_reason(reason)})
    end
  end

  get "/events/recent" do
    events = Pulsebus.recent_events() |> Enum.map(&event_to_map/1)

    send_json(conn, 200, %{events: events})
  end

  get "/events/topics" do
    send_json(conn, 200, Pulsebus.topics())
  end

  match _ do
    send_json(conn, 404, %{error: "not_found"})
  end

  defp require_json_content_type(conn) do
    case Plug.Conn.get_req_header(conn, "content-type") do
      [content_type | _] ->
        if String.starts_with?(String.downcase(content_type), "application/json") do
          :ok
        else
          {:error, :unsupported_content_type}
        end

      [] ->
        {:error, :unsupported_content_type}
    end
  end

  defp read_json_map(conn) do
    read_json(conn, fn
      decoded when is_map(decoded) -> {:ok, decoded}
      _decoded -> {:error, :invalid_request_body}
    end)
  end

  defp read_json_array(conn) do
    read_json(conn, fn
      decoded when is_list(decoded) -> {:ok, decoded}
      _decoded -> {:error, :invalid_request_body}
    end)
  end

  defp read_json(conn, validate) do
    case Plug.Conn.read_body(conn) do
      {:ok, body, _conn} ->
        decode_json(body, validate)

      {:more, _partial, _conn} ->
        {:error, :invalid_request_body}

      {:error, _reason} ->
        {:error, :invalid_request_body}
    end
  end

  defp decode_json(body, validate) do
    case Jason.decode(body) do
      {:ok, decoded} -> validate.(decoded)
      {:error, _reason} -> {:error, :invalid_json}
    end
  end

  defp send_json(conn, status, body) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(status, Jason.encode!(body))
  end

  defp event_to_map(event) do
    %{
      id: event.id,
      topic: event.topic,
      source: event.source,
      ts: event.ts,
      payload: event.payload
    }
  end

  defp format_reason({:missing_required_field, field}), do: "missing_required_field:#{field}"
  defp format_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp format_reason(reason), do: inspect(reason)
end
