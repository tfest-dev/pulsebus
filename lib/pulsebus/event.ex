defmodule Pulsebus.Event do
  @moduledoc """
  Event schema and validation for Pulsebus events.
  """

  @enforce_keys [:id, :topic, :source, :ts, :payload]
  defstruct [:id, :topic, :source, :ts, :payload]

  @type t :: %__MODULE__{
          id: String.t(),
          topic: String.t(),
          source: String.t(),
          ts: String.t(),
          payload: map()
        }

  @doc """
  Builds a validated event from caller attributes and centrally generated values.
  """
  def build(attrs, id, ts) when is_map(attrs) do
    topic = get_attr(attrs, :topic)
    source = get_attr(attrs, :source)
    payload = Map.get(attrs, :payload, Map.get(attrs, "payload", %{}))

    with :ok <- validate_required_string(topic, :topic),
         :ok <- validate_required_string(source, :source),
         :ok <- validate_payload(payload) do
      {:ok,
       %__MODULE__{
         id: id,
         topic: topic,
         source: source,
         ts: ts,
         payload: payload
       }}
    end
  end

  def build(_attrs, _id, _ts), do: {:error, :invalid_attrs}

  defp get_attr(attrs, key) do
    Map.get(attrs, key, Map.get(attrs, Atom.to_string(key)))
  end

  defp validate_required_string(value, _field)
       when is_binary(value) and byte_size(value) > 0 do
    :ok
  end

  defp validate_required_string(_value, field), do: {:error, {:missing_required_field, field}}

  defp validate_payload(payload) when is_map(payload), do: :ok
  defp validate_payload(_payload), do: {:error, :invalid_payload}
end
