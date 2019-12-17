defmodule RigInboundGatewayWeb.V1.MetadataController do
  @moduledoc """
  Handles inbound metadata sets and the indexing and distribution of metadata
  """
  use RigInboundGatewayWeb, :controller
  use RigInboundGatewayWeb.Cors, [:put, :get]
  use Rig.Config, [:cors]

  alias Result
  alias Rig.Connection.Codec
  alias RigInboundGateway.Metadata

  require Logger

  @doc """
  Sets metadata KV pairs for an existing connection, replacing previous metadata sets.

  There may be indexed metadata pairs defined. If a metadata set does not contain these indexed keys, it cannot be accepted.

  ## Example

  Metadata set that contains a user ID, locale and timezone:

      {
        "metadata": {
          "userid": "9ab1bff2-a8d8-455c-b48a-50145d7d8e30",
          "locale": "de-AT",
          "timezone": "GMT+1"
        }
      }

  In this example, the field "userid" might be indexed. In this case, the connection token would get associated with the value of the "userid" field (it will be possible to automatically take the user id from the JWT token (so that it cannot be changed by any other way) and index that; this will be serverside configuration).
  In addition to that, the value of the "userid", "locale" and "timezone" are stored in the VConnection. So when someone requests metadata from a user by a specific userid, RIG asks the VConnection(s) of that user to return it.

  So the association would look like so:

      userid -> connection token

      VConnection ->
        userid
        locale
        timezone

  All indexed fields are then being propagated to all other instances, so they know where to find the corresponding metadata.

  ## Example

  A user connects to RIG 1 and sends the metadata fields from above to RIG 1. RIG 1 would propagate the connection token and the userid along with the RIG instance ID to all other RIG instances.
  If someone were to access the metadata of a user from RIG 3, RIG 3 would know where to find the metadata, ask RIG 1 for it and return the metadata set.
  """
  @spec set_metadata(conn :: Plug.Conn.t(), params :: map) :: Plug.Conn.t()
  def set_metadata(
        %{method: "PUT"} = conn,
        %{
          "connection_id" => connection_id
        }
      ) do

    {err, data} = conn
    |> accept_only_req_for(["application/json"])
    |> Metadata.extract()

    if err === :error do
      fail!(conn, data)
    else
      persist_metadata(data, connection_id)
      send_resp(conn, :no_content, "")
    end
  end

  # ---

  defp persist_metadata({metadata, indexed_fields}, connection_id) do
    Logger.debug(fn -> "Metadata: " <> inspect(metadata) end)
    Logger.debug(fn -> "Indexed fields: " <> inspect(indexed_fields) end)

    {:ok, pid} = Codec.deserialize(connection_id)

    send pid, {:set_metadata, metadata, indexed_fields, true}
  end

  # ---

  defp fail!(conn, msg) do
    send_resp(conn, :bad_request, msg)
    Plug.Conn.halt(conn)
  end
end