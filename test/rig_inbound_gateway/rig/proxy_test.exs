defmodule RigInboundGateway.ProxyTest do
  @moduledoc false
  use ExUnit.Case, async: false
  use RigApi.ConnCase

  require Logger

  alias RigInboundGateway.Proxy
  alias RigInboundGateway.ProxyConfig

  import RigInboundGateway.Proxy,
    only: [
      list_apis: 1,
      get_api: 2,
      add_api: 3,
      replace_api: 4,
      update_api: 3,
      deactivate_api: 2,
      handle_join_api: 3
    ]

  @invalid_config_id "invalid-config"

  setup [:with_tracker_mock_proxy]

  describe "validations" do
    test "should exit the process when target is set to kafka or kinesis, but topic is not",
         ctx do
      # kinesis topic not set
      endpoints = [
        %{
          "id" => @invalid_config_id <> "1",
          "method" => "GET",
          "path" => "/foo",
          "target" => "kinesis"
        }
      ]

      set_proxy_config(@invalid_config_id, endpoints)
      kinesis_orig_value = ProxyConfig.set("PROXY_KINESIS_REQUEST_STREAM", "")

      Process.flag(:trap_exit, true)

      catch_exit do
        {:ok, proxy} = Proxy.start_link(ctx.tracker, name: nil)
        proxy |> list_apis
      end

      assert_received({:EXIT, proxy, :ReverseProxyConfigurationError})
      ProxyConfig.restore()
      ProxyConfig.restore_one("PROXY_KINESIS_REQUEST_STREAM", kinesis_orig_value)

      # kafka topic not set
      endpoints = [
        %{
          "id" => @invalid_config_id <> "1",
          "method" => "GET",
          "path" => "/foo",
          "target" => "kafka"
        }
      ]

      set_proxy_config(@invalid_config_id, endpoints)
      kafka_orig_value = ProxyConfig.set("PROXY_KAFKA_REQUEST_TOPIC", "")

      Process.flag(:trap_exit, true)

      catch_exit do
        {:ok, proxy} = Proxy.start_link(ctx.tracker, name: nil)
        proxy |> list_apis
      end

      assert_received({:EXIT, proxy, :ReverseProxyConfigurationError})
      ProxyConfig.restore()
      ProxyConfig.restore_one("PROXY_KAFKA_REQUEST_TOPIC", kafka_orig_value)
    end

    test "should exit the process when schema is set, but target is not kafka or kinesis", ctx do
      endpoints = [
        %{
          "id" => @invalid_config_id <> "1",
          "method" => "GET",
          "path" => "/foo",
          "schema" => "some-avro-schema"
        }
      ]

      set_proxy_config(@invalid_config_id, endpoints)

      Process.flag(:trap_exit, true)

      catch_exit do
        {:ok, proxy} = Proxy.start_link(ctx.tracker, name: nil)
        proxy |> list_apis
      end

      assert_received({:EXIT, proxy, :ReverseProxyConfigurationError})
      ProxyConfig.restore()
    end

    test "should exit the process when secured is set, but auth_type is not jwt", ctx do
      endpoints = [
        %{
          "id" => @invalid_config_id <> "1",
          "method" => "GET",
          "path" => "/foo",
          "secured" => true
        }
      ]

      set_proxy_config(@invalid_config_id, endpoints)

      Process.flag(:trap_exit, true)

      catch_exit do
        {:ok, proxy} = Proxy.start_link(ctx.tracker, name: nil)
        proxy |> list_apis
      end

      assert_received({:EXIT, proxy, :ReverseProxyConfigurationError})
      ProxyConfig.restore()
    end

    test "should exit the process when use_header is set, but header_name is not", ctx do
      endpoints = [
        %{
          "id" => @invalid_config_id <> "1",
          "method" => "GET",
          "path" => "/foo"
        }
      ]

      auth = %{"use_header" => true}
      auth_type = "jwt"

      set_proxy_config(@invalid_config_id, endpoints, auth, auth_type)

      Process.flag(:trap_exit, true)

      catch_exit do
        {:ok, proxy} = Proxy.start_link(ctx.tracker, name: nil)
        proxy |> list_apis
      end

      assert_received({:EXIT, proxy, :ReverseProxyConfigurationError})
      ProxyConfig.restore()
    end

    test "should exit the process when use_query is set, but query_name is not", ctx do
      endpoints = [
        %{
          "id" => @invalid_config_id <> "1",
          "method" => "GET",
          "path" => "/foo"
        }
      ]

      auth = %{"use_query" => true}
      auth_type = "jwt"

      set_proxy_config(@invalid_config_id, endpoints, auth, auth_type)

      Process.flag(:trap_exit, true)

      catch_exit do
        {:ok, proxy} = Proxy.start_link(ctx.tracker, name: nil)
        proxy |> list_apis
      end

      assert_received({:EXIT, proxy, :ReverseProxyConfigurationError})
      ProxyConfig.restore()
    end

    test "should exit the process when auth is set, but auth_type is not", ctx do
      endpoints = [
        %{
          "id" => @invalid_config_id <> "1",
          "method" => "GET",
          "path" => "/foo"
        }
      ]

      auth = %{"use_query" => true, "query_name" => "test"}

      set_proxy_config(@invalid_config_id, endpoints, auth)

      Process.flag(:trap_exit, true)

      catch_exit do
        {:ok, proxy} = Proxy.start_link(ctx.tracker, name: nil)
        proxy |> list_apis
      end

      assert_received({:EXIT, proxy, :ReverseProxyConfigurationError})
      ProxyConfig.restore()
    end
  end

  describe "list_apis" do
    test "should return API definitions when the configuration is passed as a JSON file.", ctx do
      {:ok, proxy} = Proxy.start_link(ctx.tracker, name: nil)

      assert proxy |> list_apis |> length == 2
      assert ctx.tracker |> Stubr.called_once?(:list_by_node)
    end

    test "should return API definitions when the configuration is passed as a JSON string.",
         ctx do
      id = "config-by-json-string"

      endpoints = [
        %{
          "id" => id <> "1",
          "method" => "GET",
          "secured" => false,
          "path" => "/foo"
        }
      ]

      set_proxy_config(id, endpoints)

      {:ok, proxy} = Proxy.start_link(ctx.tracker, name: nil)
      apis = Proxy.list_apis(proxy)
      assert [{^id, _api}] = apis

      ProxyConfig.restore()
    end
  end

  describe "get_api" do
    test "should return nil for non-existent API definition", ctx do
      {:ok, proxy} = Proxy.start_link(ctx.tracker, name: nil)

      assert proxy |> get_api("random-service")
      assert ctx.tracker |> Stubr.called_once?(:find_by_node)
    end
  end

  describe "add_api" do
    test "should start tracking new API and add default values for optional data", ctx do
      {:ok, proxy} = Proxy.start_link(ctx.tracker, name: nil)

      refute proxy |> get_api("incomplete-service")
      assert ctx.tracker |> Stubr.called_twice?(:track)
      assert ctx.tracker |> Stubr.called_once?(:find_by_node)

      incomplete_api = %{
        "id" => "incomplete-service",
        "name" => "incomplete-service",
        "proxy" => %{"port" => 7070, "target_url" => "API_HOST"},
        "version_data" => %{}
      }

      {:ok, _response} = proxy |> add_api("incomplete-service", incomplete_api)

      {_id, api} = proxy |> get_api("incomplete-service")

      has_required_keys =
        ["active", "auth_type", "auth", "node_name", "ref_number", "timestamp", "versioned"]
        |> Enum.all?(fn key -> Map.has_key?(api, key) end)

      assert has_required_keys
      assert ctx.tracker |> Stubr.called_thrice?(:track)
      assert ctx.tracker |> Stubr.called_twice?(:find_by_node)
    end

    test "should start tracking new API and not override optional data if present", ctx do
      {:ok, proxy} = Proxy.start_link(ctx.tracker, name: nil)

      refute proxy |> get_api("new-service")
      assert ctx.tracker |> Stubr.called_twice?(:track)
      assert ctx.tracker |> Stubr.called_once?(:find_by_node)

      {:ok, _response} = proxy |> add_api("new-service", @mock_api)
      {_id, api} = proxy |> get_api("new-service")

      has_equal_values =
        @mock_api
        |> Map.keys()
        |> Enum.all?(fn key -> @mock_api[key] == api[key] end)

      assert has_equal_values
      assert ctx.tracker |> Stubr.called_thrice?(:track)
      assert ctx.tracker |> Stubr.called_twice?(:find_by_node)
    end

    test "with existing ID should return error", ctx do
      {:ok, proxy} = Proxy.start_link(ctx.tracker, name: nil)

      {:error, :already_tracked} = proxy |> add_api("random-service", @mock_api)
      assert ctx.tracker |> Stubr.called_thrice?(:track)
    end

    test "should set default auth values for service", ctx do
      {:ok, proxy} = Proxy.start_link(ctx.tracker, name: nil)

      refute proxy |> get_api("incomplete-service")
      assert ctx.tracker |> Stubr.called_twice?(:track)
      assert ctx.tracker |> Stubr.called_once?(:find_by_node)

      api_config = %{
        "id" => "incomplete-service",
        "name" => "incomplete-service",
        "proxy" => %{"port" => 7070, "target_url" => "API_HOST"},
        "version_data" => %{},
        "auth_type" => "none"
      }

      expected_auth_values = %{
        "use_header" => false,
        "header_name" => "",
        "use_query" => false,
        "query_name" => ""
      }

      {:ok, _response} = proxy |> add_api("incomplete-service", api_config)

      {_id, api} = proxy |> get_api("incomplete-service")

      assert api["auth"] == expected_auth_values

      assert ctx.tracker |> Stubr.called_thrice?(:track)
      assert ctx.tracker |> Stubr.called_twice?(:find_by_node)
    end

    test "should set header auth values if auth_type is jwt", ctx do
      {:ok, proxy} = Proxy.start_link(ctx.tracker, name: nil)

      refute proxy |> get_api("incomplete-service")
      assert ctx.tracker |> Stubr.called_twice?(:track)
      assert ctx.tracker |> Stubr.called_once?(:find_by_node)

      api_config = %{
        "id" => "incomplete-service",
        "name" => "incomplete-service",
        "proxy" => %{"port" => 7070, "target_url" => "API_HOST"},
        "version_data" => %{},
        "auth_type" => "jwt"
      }

      expected_auth_values = %{
        "use_header" => true,
        "header_name" => "Authorization",
        "use_query" => false,
        "query_name" => ""
      }

      {:ok, _response} = proxy |> add_api("incomplete-service", api_config)

      {_id, api} = proxy |> get_api("incomplete-service")

      assert api["auth"] == expected_auth_values

      assert ctx.tracker |> Stubr.called_thrice?(:track)
      assert ctx.tracker |> Stubr.called_twice?(:find_by_node)
    end

    test "should not override user defined query auth values when auth_type is jwt", ctx do
      {:ok, proxy} = Proxy.start_link(ctx.tracker, name: nil)

      refute proxy |> get_api("incomplete-service")
      assert ctx.tracker |> Stubr.called_twice?(:track)
      assert ctx.tracker |> Stubr.called_once?(:find_by_node)

      api_config = %{
        "id" => "incomplete-service",
        "name" => "incomplete-service",
        "proxy" => %{"port" => 7070, "target_url" => "API_HOST"},
        "version_data" => %{},
        "auth_type" => "jwt",
        "auth" => %{
          "use_query" => true,
          "query_name" => "token"
        }
      }

      {:ok, _response} = proxy |> add_api("incomplete-service", api_config)

      {_id, api} = proxy |> get_api("incomplete-service")

      assert api["auth"]["use_query"]
      assert api["auth"]["query_name"] == "token"

      # auth type set to jwt should still set the appropiate auth values
      assert api["auth"]["use_header"]
      assert api["auth"]["header_name"] == "Authorization"

      assert ctx.tracker |> Stubr.called_thrice?(:track)
      assert ctx.tracker |> Stubr.called_twice?(:find_by_node)
    end
  end

  describe "replace_api" do
    test "should replace deactivated API with new one", ctx do
      {:ok, proxy} = Proxy.start_link(ctx.tracker, name: nil)

      proxy |> deactivate_api("random-service")

      {_id, deactivated_api} = proxy |> get_api("random-service")
      assert deactivated_api["active"] == false
      assert ctx.tracker |> Stubr.called_once?(:update)

      proxy |> replace_api("random-service", deactivated_api, @mock_api)

      {_id, replaced_api} = proxy |> get_api("random-service")
      assert replaced_api["active"] == true

      assert ctx.tracker |> Stubr.called_twice?(:update)
    end
  end

  describe "update_api" do
    test "should update existing API", ctx do
      {:ok, proxy} = Proxy.start_link(ctx.tracker, name: nil)

      {_id, existing_api} = proxy |> get_api("random-service")
      assert existing_api["name"] == "random-service"

      refute ctx.tracker |> Stubr.called?(:update)
      updated_existing_api = existing_api |> Map.put("name", "updated-service")
      proxy |> update_api("random-service", updated_existing_api)

      {_id, new_api} = proxy |> get_api("random-service")

      assert new_api["name"] == "updated-service"
      assert ctx.tracker |> Stubr.called_once?(:update)
    end
  end

  describe "deactivate_api" do
    test "should deactivate API ", ctx do
      {:ok, proxy} = Proxy.start_link(ctx.tracker, name: nil)

      {_id, current_api} = proxy |> get_api("random-service")
      assert current_api["active"] == true

      refute ctx.tracker |> Stubr.called?(:update)
      proxy |> deactivate_api("random-service")

      {_id, deactivated_api} = proxy |> get_api("random-service")
      assert deactivated_api["active"] == false
      assert ctx.tracker |> Stubr.called_once?(:update)
    end
  end

  describe "handle_join_api" do
    test "should track new API", ctx do
      {:ok, proxy} = Proxy.start_link(ctx.tracker, name: nil)

      proxy |> handle_join_api("new-service", @mock_api)

      :timer.sleep(25)
      assert proxy |> get_api("new-service")
      refute ctx.tracker |> Stubr.called?(:update)
    end
  end

  describe "handle_join_api receiving existing API" do
    test "should skip API when it has out of date ref_number", ctx do
      {:ok, proxy} = Proxy.start_link(ctx.tracker, name: nil)

      older_api =
        proxy
        |> get_api("random-service")
        |> elem(1)
        |> Map.put("ref_number", -1)

      proxy |> handle_join_api("random-service", older_api)

      {_id, current_api} = proxy |> get_api("random-service")

      :timer.sleep(25)
      assert current_api["ref_number"] == 0
      refute ctx.tracker |> Stubr.called?(:update)
    end

    test "should update API when it has more recent ref_number", ctx do
      {:ok, proxy} = Proxy.start_link(ctx.tracker, name: nil)

      newer_api =
        proxy
        |> get_api("random-service")
        |> elem(1)
        |> Map.put("ref_number", 1)

      refute ctx.tracker |> Stubr.called?(:update)
      proxy |> handle_join_api("random-service", newer_api)

      {_id, current_api} = proxy |> get_api("random-service")

      :timer.sleep(25)
      assert current_api["ref_number"] == 1
      assert ctx.tracker |> Stubr.called_once?(:update)
    end

    test "with same ref_number and equal data should skip API", ctx do
      {:ok, proxy} = Proxy.start_link(ctx.tracker, name: nil)

      {_id, equal_api} = proxy |> get_api("random-service")

      proxy |> handle_join_api("random-service", equal_api)

      {_id, current_api} = proxy |> get_api("random-service")

      :timer.sleep(25)
      assert current_api["ref_number"] == 0
      refute ctx.tracker |> Stubr.called?(:update)
    end
  end

  describe "handle_join_api receiving existing API with same ref_number and different data" do
    test "on less than 1/2 nodes should skip API", ctx do
      {:ok, proxy} = Proxy.start_link(ctx.tracker, name: nil)

      node2_api = @mock_api |> Map.put("node_name", :node2@node2)
      node3_api = @mock_api |> Map.put("node_name", :node3@node3)

      proxy |> add_api("new-service", @mock_api)
      proxy |> add_api("new-service", node2_api)
      proxy |> add_api("new-service", node3_api)

      different_api =
        @mock_api
        |> Map.put("ref_number", 0)
        |> Map.put("name", "new_name")

      proxy |> handle_join_api("new-service", different_api)

      :timer.sleep(25)
      refute ctx.tracker |> Stubr.called?(:update)
    end

    test "on more than 1/2 nodes should update API", ctx do
      {:ok, proxy} = Proxy.start_link(ctx.tracker, name: nil)

      different_api =
        @mock_api
        |> Map.put("name", "new_name")
        |> Map.put("ref_number", 0)

      node2_api = different_api |> Map.put("node_name", :node2@node2)
      node3_api = different_api |> Map.put("node_name", :node3@node3)

      proxy |> add_api("new-service", @mock_api)
      ctx.tracker.track("new-service", node2_api)
      ctx.tracker.track("new-service", node3_api)
      refute ctx.tracker |> Stubr.called?(:update)

      proxy |> handle_join_api("new-service", different_api)

      {_id, current_api} = proxy |> get_api("new-service")

      :timer.sleep(25)
      assert current_api["ref_number"] == 0
      assert current_api["name"] == "new_name"
      assert ctx.tracker |> Stubr.called_once?(:update)
    end

    test "on exactly 1/2 nodes, but old timestamp should skip API", ctx do
      {:ok, proxy} = Proxy.start_link(ctx.tracker, name: nil)

      old_timestamp = Timex.now() |> Timex.shift(minutes: -3)

      different_api =
        @mock_api
        |> Map.put("ref_number", 0)
        |> Map.put("name", "new_name")
        |> Map.put("node_name", :differentnode@differenthost)
        |> Map.put("timestamp", old_timestamp)

      proxy |> add_api("new-service", @mock_api)
      proxy |> add_api("new-service", different_api)

      proxy |> handle_join_api("new-service", different_api)

      :timer.sleep(25)
      refute ctx.tracker |> Stubr.called?(:update)
    end

    test "on exactly 1/2 nodes and newer timestamp should update API", ctx do
      {:ok, proxy} = Proxy.start_link(ctx.tracker, name: nil)

      new_timestamp = Timex.now() |> Timex.shift(minutes: +3)

      different_api =
        @mock_api
        |> Map.put("ref_number", 0)
        |> Map.put("name", "new_name")
        |> Map.put("node_name", :differentnode@differenthost)
        |> Map.put("timestamp", new_timestamp)

      proxy |> add_api("new-service", @mock_api)
      ctx.tracker.track("new-service", different_api)
      refute ctx.tracker |> Stubr.called?(:update)

      proxy |> handle_join_api("new-service", different_api)

      :timer.sleep(25)
      assert ctx.tracker |> Stubr.called_once?(:update)
    end
  end

  defp set_proxy_config(id, endpoints, auth \\ %{}, auth_type \\ nil) do
    ProxyConfig.set([
      %{
        "active" => true,
        "id" => id,
        "name" => id,
        "proxy" => %{
          "port" => 3000,
          "target_url" => "http://localhost",
          "use_env" => false
        },
        "version_data" => %{
          "default" => %{
            "endpoints" => endpoints
          }
        },
        "versioned" => false,
        "auth" => auth,
        "auth_type" => auth_type
      }
    ])
  end

  defp with_tracker_mock_proxy(_ctx) do
    {:ok, agent} = Agent.start_link(fn -> [] end)

    tracker =
      Stubr.stub!(
        [
          track: fn id, api ->
            Logger.debug(fn -> "Tracker Stub :track id=#{inspect(id)} api=#{inspect(api)}" end)
            # Mimic the "cannot track more than once" behaviour:
            already_tracked? =
              Agent.get(agent, fn list ->
                list
                |> Enum.find(fn {key, meta} ->
                  key == id && meta["node_name"] == api["node_name"]
                end)
              end) != nil

            if already_tracked? do
              {:error, :already_tracked}
            else
              Agent.update(agent, fn list ->
                api_with_ref = api |> Map.put(:phx_ref, "some_phx_ref")
                [{id, api_with_ref} | list]
              end)

              {:ok, 'some_phx_ref'}
            end
          end,
          update: fn id, api ->
            Logger.debug(fn -> "Tracker Stub :update id=#{inspect(id)} api=#{inspect(api)}" end)

            Agent.update(agent, fn list ->
              list
              |> Enum.filter(fn {key, meta} ->
                key != id || meta["node_name"] != :nonode@nohost
              end)
              |> Enum.concat([{id, api}])
            end)

            {:ok, 'some_phx_ref'}
          end,
          list_all: fn ->
            Logger.debug("Tracker Stub :list")
            Agent.get(agent, fn list -> list end)
          end,
          list_by_node: fn node_name ->
            Logger.debug("Tracker Stub :list")

            Agent.get(agent, fn list ->
              list |> Enum.filter(fn {_key, meta} -> meta["node_name"] == node_name end)
            end)
          end,
          # was _node_name
          find_by_node: fn id, node_name ->
            Logger.debug(fn -> "Tracker Stub :find id=#{inspect(id)}" end)

            Agent.get(agent, fn list ->
              list
              |> Enum.find(fn {key, meta} ->
                key == id && meta["node_name"] == node_name
              end)
            end)
          end,
          find_all: fn id ->
            Logger.debug(fn -> "Tracker Stub :find_all id=#{inspect(id)}" end)
            Agent.get(agent, fn list -> list |> Enum.filter(fn {key, _meta} -> key == id end) end)
          end
        ],
        behaviour: RigInboundGateway.ApiProxy.Tracker.TrackerBehaviour,
        call_info: true
      )

    [tracker: tracker]
  end
end
