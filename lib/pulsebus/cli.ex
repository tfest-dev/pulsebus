defmodule Pulsebus.CLI do
  @moduledoc """
  Minimal command-line client for a running local Pulsebus HTTP service.
  """

  @default_base_url "http://127.0.0.1:4040"

  def main(argv) do
    argv
    |> run(System.get_env(), Pulsebus.CLI.HTTPClient)
    |> System.halt()
  end

  def run(argv, env \\ System.get_env(), http_client \\ Pulsebus.CLI.HTTPClient) do
    with {:ok, command} <- parse(argv, env),
         {:ok, request} <- build_request(command),
         {:ok, response} <-
           http_client.request(request.method, request.url, request.headers, request.body) do
      handle_response(command.name, response)
    else
      {:error, reason} ->
        print_error(reason)
        1
    end
  end

  def parse(argv, env \\ System.get_env())

  def parse(["health"], env) do
    {:ok, %{name: :health, base_url: base_url(env)}}
  end

  def parse(["recent"], env) do
    {:ok, %{name: :recent, base_url: base_url(env)}}
  end

  def parse(["topics"], env) do
    {:ok, %{name: :topics, base_url: base_url(env)}}
  end

  def parse(["emit" | args], env) do
    parse_emit(args, env)
  end

  def parse([], _env), do: {:error, :missing_command}
  def parse([command | _args], _env), do: {:error, {:unknown_command, command}}

  def build_request(%{name: :health, base_url: base_url}) do
    {:ok, %{method: :get, url: base_url <> "/health", headers: [], body: nil}}
  end

  def build_request(%{name: :recent, base_url: base_url}) do
    {:ok, %{method: :get, url: base_url <> "/events/recent", headers: [], body: nil}}
  end

  def build_request(%{name: :topics, base_url: base_url}) do
    {:ok, %{method: :get, url: base_url <> "/events/topics", headers: [], body: nil}}
  end

  def build_request(%{
        name: :emit,
        base_url: base_url,
        topic: topic,
        source: source,
        payload: payload
      }) do
    body = Jason.encode!(%{topic: topic, source: source, payload: payload})

    {:ok,
     %{
       method: :post,
       url: base_url <> "/events",
       headers: [{~c"content-type", ~c"application/json"}],
       body: body
     }}
  end

  defp parse_emit([], _env), do: {:error, :missing_topic}

  defp parse_emit([topic | args], env) do
    with {:ok, opts} <- parse_emit_opts(args, %{source: nil, payload: %{}}),
         :ok <- require_source(opts.source) do
      {:ok,
       %{
         name: :emit,
         base_url: base_url(env),
         topic: topic,
         source: opts.source,
         payload: opts.payload
       }}
    end
  end

  defp parse_emit_opts([], opts), do: {:ok, opts}

  defp parse_emit_opts(["--source", source | rest], opts) do
    parse_emit_opts(rest, %{opts | source: source})
  end

  defp parse_emit_opts(["--source"], _opts), do: {:error, :missing_source}

  defp parse_emit_opts(["--json", json | rest], opts) do
    case Jason.decode(json) do
      {:ok, payload} when is_map(payload) ->
        parse_emit_opts(rest, %{opts | payload: payload})

      {:ok, _payload} ->
        {:error, :payload_not_object}

      {:error, _reason} ->
        {:error, :invalid_json}
    end
  end

  defp parse_emit_opts(["--json"], _opts), do: {:error, :invalid_json}
  defp parse_emit_opts([flag | _rest], _opts), do: {:error, {:unknown_option, flag}}

  defp require_source(source) when is_binary(source) and byte_size(source) > 0, do: :ok
  defp require_source(_source), do: {:error, :missing_source}

  defp base_url(env) do
    env
    |> Map.get("PULSEBUS_URL", @default_base_url)
    |> String.trim_trailing("/")
  end

  defp handle_response(:health, %{status: 200}) do
    IO.puts("Pulsebus is running")
    0
  end

  defp handle_response(:recent, %{status: 200, body: body}) do
    case Jason.decode(body) do
      {:ok, %{"events" => []}} ->
        IO.puts("No recent events")
        0

      {:ok, %{"events" => events}} when is_list(events) ->
        Enum.each(events, &print_event/1)
        0

      _other ->
        print_error(:invalid_response)
        1
    end
  end

  defp handle_response(:topics, %{status: 200, body: body}) do
    case Jason.decode(body) do
      {:ok, topics} when is_list(topics) ->
        IO.puts(format_topics(topics))
        0

      _other ->
        print_error(:invalid_response)
        1
    end
  end

  defp handle_response(:emit, %{status: 201, body: body}) do
    case Jason.decode(body) do
      {:ok, %{"id" => id, "topic" => topic}} ->
        IO.puts("Emitted #{id} #{topic}")
        0

      _other ->
        print_error(:invalid_response)
        1
    end
  end

  defp handle_response(_command, %{status: status, body: body}) when status >= 400 do
    message =
      case Jason.decode(body) do
        {:ok, %{"error" => error, "reason" => reason}} -> "#{error}: #{reason}"
        {:ok, %{"error" => error}} -> error
        _other -> "HTTP #{status}"
      end

    print_error(message)
    1
  end

  defp handle_response(_command, %{status: status}) do
    print_error("HTTP #{status}")
    1
  end

  defp print_event(event) do
    id = Map.get(event, "id", "?")
    topic = Map.get(event, "topic", "?")
    source = Map.get(event, "source", "?")
    ts = Map.get(event, "ts", "?")

    IO.puts("#{ts} #{id} #{topic} source=#{source}")
  end

  @doc false
  def format_topics([]), do: "No recent topics"

  def format_topics(topics) when is_list(topics) do
    width =
      topics
      |> Enum.map(fn topic -> topic |> Map.get("topic", "?") |> String.length() end)
      |> Enum.max()

    rows =
      Enum.map(topics, fn topic ->
        name = Map.get(topic, "topic", "?")
        count = Map.get(topic, "count", "?")
        last_seen = Map.get(topic, "last_seen", "?")

        "#{String.pad_trailing(name, width)} count=#{count} last_seen=#{last_seen}"
      end)

    Enum.join(["Recent topics:", "" | rows], "\n")
  end

  defp print_error(reason) do
    IO.puts(:stderr, "Error: #{format_error(reason)}")
  end

  defp format_error(:missing_command), do: "missing command"
  defp format_error(:missing_topic), do: "emit requires a topic"
  defp format_error(:missing_source), do: "emit requires --source"
  defp format_error(:invalid_json), do: "--json must be valid JSON"
  defp format_error(:payload_not_object), do: "--json must decode to an object"
  defp format_error(:invalid_response), do: "invalid response from Pulsebus"
  defp format_error({:unknown_command, command}), do: "unknown command #{command}"
  defp format_error({:unknown_option, option}), do: "unknown option #{option}"
  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)
end
