defmodule Gateway.ApiProxy.PresenceHandler do
  @moduledoc """
  Handles Phoenix Presence events.

  Implemented as a Phoenix.Tracker, this module tracks all events it receives
  from the given Phoenix PubSub server. Only join/leave/update events that refer
  to the `@proxy` topic are considered for inclusion into the PROXY.

  The PROXY server is started from, and linked against, this server.

  """
  require Logger
  @behaviour Phoenix.Tracker

  alias Gateway.Proxy

  @topic "proxy"

  def start_link(opts) do
    opts = Keyword.merge([name: __MODULE__], opts)
    GenServer.start_link(
      Phoenix.Tracker,
      [__MODULE__, opts, opts],
      name: __MODULE__)
  end

  # callbacks

  @impl Phoenix.Tracker
  def init(opts) do
    {:ok, proxy} = Proxy.start_link()
    pubsub = Keyword.fetch!(opts, :pubsub_server)

    {:ok, %{
      pubsub_server: pubsub,
      node_name: Phoenix.PubSub.node_name(pubsub),
      proxy: proxy,
      }
    }
  end

  @doc """
  Forwards joins/leaves/updates on the "proxy" topic to the Proxy server.

  """
  @impl Phoenix.Tracker
  def handle_diff(diff, state) do
    for {topic, {joins, leaves}} <- diff do
      for {key, meta} <- joins do
        if topic == @topic do
          [id, api] = [key, Map.delete(meta, :phx_ref)]
          state.proxy |> Proxy.add_api(id, api)
        end
        msg = {:join, key, meta}
        Phoenix.PubSub.direct_broadcast!(state.node_name, state.pubsub_server, topic, msg)
      end
      for {key, meta} <- leaves do
        msg = {:leave, key, meta}
        Phoenix.PubSub.direct_broadcast!(state.node_name, state.pubsub_server, topic, msg)
      end
    end
    {:ok, state}
  end
end