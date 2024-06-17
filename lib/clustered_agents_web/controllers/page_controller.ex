defmodule ClusteredAgentsWeb.PageController do
  use ClusteredAgentsWeb, :controller

  alias Horde.Cluster

  def home(conn, _params) do
    # The home page is often custom made,
    # so skip the default app layout.
    render(conn, :home, layout: false)
  end

  def cluster(conn, _params) do
    render(conn, :cluster,
      supervisors: Cluster.members(ClusteredAgents.StateSupervisor),
      registries: Cluster.members(ClusteredAgents.Registry)
    )
  end
end
