defmodule ClusteredAgentsWeb.PageHTML do
  use ClusteredAgentsWeb, :html

  embed_templates "page_html/*"

  def cluster(assigns) do
    ~H"""
    <h1>Cluster Information</h1>

    <div>
      <h2>Dynamic Supervisors</h2>
      <ul :for={{_, node_name} <- @supervisors}>
        <li><%= node_name %></li>
      </ul>
    </div>

    <div>
      <h2>Registries</h2>
      <ul :for={{_, node_name} <- @registries}>
        <li><%= node_name %></li>
      </ul>
    </div>
    """
  end
end
