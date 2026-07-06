defmodule Pulsebus.CLITest do
  use ExUnit.Case, async: true

  alias Pulsebus.CLI

  @default_url "http://127.0.0.1:4040"

  test "parses health" do
    assert CLI.parse(["health"], %{}) == {:ok, %{name: :health, base_url: @default_url}}
  end

  test "parses recent" do
    assert CLI.parse(["recent"], %{}) == {:ok, %{name: :recent, base_url: @default_url}}
  end

  test "parses topics" do
    assert CLI.parse(["topics"], %{}) == {:ok, %{name: :topics, base_url: @default_url}}
  end

  test "parses import" do
    assert CLI.parse(["import", "pulsebus_events.jsonl"], %{}) ==
             {:ok,
              %{
                name: :import,
                base_url: @default_url,
                path: "pulsebus_events.jsonl"
              }}
  end

  test "parses valid emit" do
    assert CLI.parse(
             [
               "emit",
               "repo.tests.failed",
               "--source",
               "repo",
               "--json",
               ~s({"cmd":"cargo test"})
             ],
             %{}
           ) ==
             {:ok,
              %{
                name: :emit,
                base_url: @default_url,
                topic: "repo.tests.failed",
                source: "repo",
                payload: %{"cmd" => "cargo test"}
              }}
  end

  test "missing emit topic fails" do
    assert CLI.parse(["emit"], %{}) == {:error, :missing_topic}
  end

  test "missing source fails" do
    assert CLI.parse(["emit", "repo.tests.failed"], %{}) == {:error, :missing_source}
  end

  test "invalid JSON payload fails" do
    assert CLI.parse(["emit", "repo.tests.failed", "--source", "repo", "--json", "{bad"], %{}) ==
             {:error, :invalid_json}
  end

  test "JSON array payload fails because payload must be an object" do
    assert CLI.parse(["emit", "repo.tests.failed", "--source", "repo", "--json", "[1,2]"], %{}) ==
             {:error, :payload_not_object}
  end

  test "JSON string payload fails because payload must be an object" do
    assert CLI.parse(["emit", "repo.tests.failed", "--source", "repo", "--json", ~s("bad")], %{}) ==
             {:error, :payload_not_object}
  end

  test "default payload becomes empty object" do
    assert {:ok, command} = CLI.parse(["emit", "repo.tests.failed", "--source", "repo"], %{})

    assert command.payload == %{}
  end

  test "base URL default is local" do
    assert {:ok, request} =
             CLI.parse(["health"], %{})
             |> then(fn {:ok, command} -> CLI.build_request(command) end)

    assert request.url == @default_url <> "/health"
  end

  test "PULSEBUS_URL override is respected" do
    env = %{"PULSEBUS_URL" => "http://127.0.0.1:5050/"}

    assert {:ok, request} =
             CLI.parse(["recent"], env)
             |> then(fn {:ok, command} -> CLI.build_request(command) end)

    assert request.url == "http://127.0.0.1:5050/events/recent"
  end

  test "builds topics request" do
    assert {:ok, request} =
             CLI.parse(["topics"], %{})
             |> then(fn {:ok, command} -> CLI.build_request(command) end)

    assert request.method == :get
    assert request.url == @default_url <> "/events/topics"
    assert request.headers == []
    assert request.body == nil
  end

  test "builds import request from JSONL file" do
    path =
      temp_jsonl("valid_import", [
        ~s({"id":"evt_logged_001","topic":"repo.tests.failed","source":"file","ts":"2026-07-01T09:30:00Z","payload":{}})
      ])

    assert {:ok, command} = CLI.parse(["import", path], %{})
    assert {:ok, request} = CLI.build_request(command)

    assert request.method == :post
    assert request.url == @default_url <> "/events/import"
    assert request.headers == [{~c"content-type", ~c"application/json"}]

    assert Jason.decode!(request.body) == [
             %{
               "id" => "evt_logged_001",
               "topic" => "repo.tests.failed",
               "source" => "file",
               "ts" => "2026-07-01T09:30:00Z",
               "payload" => %{}
             }
           ]
  end

  test "builds emit request body" do
    assert {:ok, command} =
             CLI.parse(
               ["emit", "repo.tests.failed", "--source", "repo", "--json", ~s({"exit_code":101})],
               %{}
             )

    assert {:ok, request} = CLI.build_request(command)

    assert request.method == :post
    assert request.url == @default_url <> "/events"

    assert Jason.decode!(request.body) == %{
             "topic" => "repo.tests.failed",
             "source" => "repo",
             "payload" => %{"exit_code" => 101}
           }
  end

  test "formats topics output preserving order" do
    assert CLI.format_topics([
             %{
               "topic" => "repo.tests.failed",
               "count" => 3,
               "last_seen" => "2026-07-01T09:30:00Z"
             },
             %{
               "topic" => "codex.run.finished",
               "count" => 1,
               "last_seen" => "2026-07-01T09:27:00Z"
             }
           ]) ==
             """
             Recent topics:

             repo.tests.failed  count=3 last_seen=2026-07-01T09:30:00Z
             codex.run.finished count=1 last_seen=2026-07-01T09:27:00Z\
             """
  end

  test "formats empty topics output" do
    assert CLI.format_topics([]) == "No recent topics"
  end

  test "CLI JSONL decoding skips blank lines" do
    contents = """

    {"id":"evt_logged_001","topic":"repo.tests.failed","source":"file","ts":"2026-07-01T09:30:00Z","payload":{}}

    """

    assert {:ok, %{events: [event], failed: 0, errors: []}} = CLI.decode_jsonl_import(contents)
    assert event["id"] == "evt_logged_001"
  end

  test "CLI invalid JSONL handling is clear" do
    contents = """
    {bad
    ["not", "object"]
    {"id":"evt_logged_001","topic":"repo.tests.failed","source":"file","ts":"2026-07-01T09:30:00Z","payload":{}}
    """

    assert {:ok,
            %{
              events: [_event],
              failed: 2,
              errors: [
                %{line: 1, reason: "invalid_json"},
                %{line: 2, reason: "not_an_object"}
              ]
            }} = CLI.decode_jsonl_import(contents)
  end

  test "CLI import fails when all lines are invalid" do
    assert CLI.decode_jsonl_import("{bad\n[]\n") == {:error, {:no_valid_import_events, 2}}
  end

  test "formats import summary with local skipped lines" do
    assert CLI.format_import_summary(%{"imported" => 2, "failed" => 1}, %{local_failed: 3}) ==
             "Imported 2 events, failed 4"
  end

  defp temp_jsonl(name, lines) do
    path = Path.join(System.tmp_dir!(), "pulsebus_cli_#{name}_#{System.unique_integer()}.jsonl")
    File.write!(path, Enum.join(lines, "\n"))
    on_exit(fn -> File.rm(path) end)
    path
  end
end
