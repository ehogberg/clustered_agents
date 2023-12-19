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
      # Start the Finch HTTP client for sending emails
      {Finch, name: ClusteredAgents.Finch},
      # Start a worker by calling: ClusteredAgents.Worker.start_link(arg)
      # {ClusteredAgents.Worker, arg},
      # Start to serve requests, typically the last entry
      ClusteredAgentsWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ClusteredAgents.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ClusteredAgentsWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
