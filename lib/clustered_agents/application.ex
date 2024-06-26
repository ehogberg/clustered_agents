defmodule ClusteredAgents.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      ClusteredAgentsWeb.Telemetry,
      {Phoenix.PubSub, name: ClusteredAgents.PubSub},
      cluster_supervisor_spec(),
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
      {Horde.DynamicSupervisor,
       name: ClusteredAgents.StateSupervisor, strategy: :one_for_one, members: :auto},
      {Horde.Registry, name: ClusteredAgents.Registry, keys: :unique, members: :auto}
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

  defp cluster_supervisor_spec() do
    topologies =
      Application.get_env(
        :clustered_agents,
        :cluster_topologies
      ) || []

    {
      Cluster.Supervisor,
      [topologies, [name: ClusteredAgents.ClusterSupervisor]]
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
