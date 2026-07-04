defmodule Pulsebus.CLI.HTTPClient do
  @moduledoc false

  def request(method, url, headers, body) do
    :inets.start()

    {method, request} = request_args(method, url, headers, body)

    method
    |> :httpc.request(request, [], body_format: :binary)
    |> normalize_response()
  end

  defp request_args(:get, url, headers, nil) do
    {:get, {String.to_charlist(url), headers}}
  end

  defp request_args(:post, url, headers, body) do
    content_type = content_type(headers)
    {:post, {String.to_charlist(url), headers, content_type, body}}
  end

  defp content_type(headers) do
    {_key, value} =
      Enum.find(headers, {"content-type", "application/octet-stream"}, fn {key, _value} ->
        String.downcase(to_string(key)) == "content-type"
      end)

    to_charlist(value)
  end

  defp normalize_response({:ok, {{_version, status, _reason}, _headers, body}}) do
    {:ok, %{status: status, body: body}}
  end

  defp normalize_response({:error, reason}), do: {:error, reason}
end
