defmodule Pulsebus.HTTP.RouterTest do
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  @opts Pulsebus.HTTP.Router.init([])

  defp request(method, path, body \\ nil, headers \\ []) do
    method
    |> conn(path, body)
    |> put_req_headers(headers)
    |> Pulsebus.HTTP.Router.call(@opts)
  end

  defp put_req_headers(conn, headers) do
    Enum.reduce(headers, conn, fn {key, value}, conn ->
      put_req_header(conn, key, value)
    end)
  end

  defp json_response(conn) do
    Jason.decode!(conn.resp_body)
  end

  test "GET /health returns 200" do
    conn = request(:get, "/health")

    assert conn.status == 200
    assert json_response(conn) == %{"status" => "ok"}
  end

  test "POST /events with valid JSON returns 201 and generated event fields" do
    body = ~s({"topic":"repo.tests.failed","source":"repo","payload":{"cmd":"cargo test"}})

    conn = request(:post, "/events", body, [{"content-type", "application/json"}])

    assert conn.status == 201

    event = json_response(conn)
    assert event["id"] =~ ~r/^evt_\d{6}$/
    assert event["topic"] == "repo.tests.failed"
    assert event["source"] == "repo"
    assert event["payload"] == %{"cmd" => "cargo test"}
    assert {:ok, _datetime, 0} = DateTime.from_iso8601(event["ts"])
  end

  test "POST /events missing topic returns 400" do
    conn =
      request(:post, "/events", ~s({"source":"repo"}), [{"content-type", "application/json"}])

    assert conn.status == 400
    assert json_response(conn)["error"] == "validation_failed"
  end

  test "POST /events missing source returns 400" do
    conn =
      request(:post, "/events", ~s({"topic":"repo.tests.failed"}), [
        {"content-type", "application/json"}
      ])

    assert conn.status == 400
    assert json_response(conn)["error"] == "validation_failed"
  end

  test "POST /events with non-map payload returns 400" do
    conn =
      request(
        :post,
        "/events",
        ~s({"topic":"repo.tests.failed","source":"repo","payload":"bad"}),
        [
          {"content-type", "application/json"}
        ]
      )

    assert conn.status == 400
    assert json_response(conn)["error"] == "validation_failed"
  end

  test "POST /events with invalid JSON returns 400" do
    conn = request(:post, "/events", "{bad", [{"content-type", "application/json"}])

    assert conn.status == 400
    assert json_response(conn) == %{"error" => "invalid_json"}
  end

  test "GET /events/recent returns events newest-first" do
    first =
      request(:post, "/events", ~s({"topic":"http.recent.first","source":"test"}), [
        {"content-type", "application/json"}
      ])
      |> json_response()

    second =
      request(:post, "/events", ~s({"topic":"http.recent.second","source":"test"}), [
        {"content-type", "application/json"}
      ])
      |> json_response()

    conn = request(:get, "/events/recent")

    assert conn.status == 200

    %{"events" => [latest, previous | _]} = json_response(conn)
    assert latest["id"] == second["id"]
    assert previous["id"] == first["id"]
  end

  test "HTTP emission notifies matching subscribers" do
    assert :ok = Pulsebus.subscribe("http.subscriber.*")

    conn =
      request(:post, "/events", ~s({"topic":"http.subscriber.matched","source":"test"}), [
        {"content-type", "application/json"}
      ])

    assert conn.status == 201
    assert %{"id" => id} = json_response(conn)
    assert_receive {:pulsebus_event, %{id: ^id, topic: "http.subscriber.matched"}}
  end
end
