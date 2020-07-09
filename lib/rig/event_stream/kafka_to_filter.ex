defmodule Rig.EventStream.KafkaToFilter do
  @moduledoc """
  Consumes events and forwards them to the event filter by event type.

  """
  use Rig.KafkaConsumerSetup

  alias Rig.EventFilter

  # ---

  def validate(conf), do: {:ok, conf}

  # ---

  def kafka_handler(body, headers) do
    case Cloudevents.from_kafka_message(body, headers) do
      {:ok, cloud_event} ->
        Logger.debug(fn -> inspect(cloud_event) end)
        EventFilter.forward_event(cloud_event)
        :ok

      {:error, _reason} ->
        {:error, :non_cloud_events_not_supported, body}
    end
  rescue
    err -> {:error, err, body}
  end
end
