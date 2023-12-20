defmodule ClusteredAgents.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      ClusteredAgentsWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:clustered_agents, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: ClusteredAgents.PubSub},
      state_collection_supervisor_spec(),
      # Start to serve requests, typically the last entry
      ClusteredAgentsWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ClusteredAgents.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp state_collection_supervisor_spec() do
    child_specs = [
      {DynamicSupervisor, name: ClusteredAgents.StateSupervisor,
        strategy: :one_for_one},
      {Registry, name: ClusteredAgents.Registry, keys: :unique}
    ]

    opts = [
      strategy: :one_for_one,
      name: ClusteredAgents.StateCollectionSupervisor
    ]

    %{
      id: ClusteredAgents.StateCollectionSupervisor,
      type: :supervisor,
      restart: :permanent,
      start: {Supervisor, :start_link, [child_specs, opts]}
    }
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ClusteredAgentsWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
