defmodule ClusteredAgentsWeb.StateLive do
  use ClusteredAgentsWeb, :live_view

  def mount(_, _, socket) do
    {
      :ok,
      socket
      |> assign_cluster_nodes()
      |> IO.inspect()
    }
  end

  defp assign_cluster_nodes(socket) do
    assign(socket, :cluster_nodes, Node.list())
  end
end
