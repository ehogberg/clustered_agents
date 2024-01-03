defmodule ClusteredAgentsWeb.StateLive do
  use ClusteredAgentsWeb, :live_view
  alias ClusteredAgents.State
  alias ClusteredAgentsWeb.Endpoint
  require Logger

  @impl true
  def mount(_, _, socket) do
    Endpoint.subscribe("agents")

    :net_kernel.monitor_nodes(true)

    {
      :ok,
      socket
      |> assign_cluster_nodes()
      |> assign_form(State.changeset(%State{}))
      |> assign_agent_list()
      |> assign_persistence_type(:add)
    }
  end

  defp assign_cluster_nodes(socket),
   do: assign(socket, :cluster_nodes, [Node.self() | Node.list()])

  defp assign_form(socket, cs), do: assign(socket, :form , to_form(cs))

  defp assign_persistence_type(socket, persistence_type),
    do: assign(socket, :persistence_type, persistence_type)

  defp assign_agent_list(socket) do
    agent_list =
      Enum.map(
        State.state_ids(),
        fn {id,pid} -> %{id: id, pid: pid, node: node(pid)} end
      )
      stream(socket, :agent_list, agent_list)
  end

  @impl true
  def handle_event("validate", %{"state" => params}, socket) do
    cs = %State{}
    |> State.changeset(params)
    |> Map.put(:action, :validate)

    {
      :noreply,
      socket
      |> assign_form(cs)
    }
  end

  @impl true
  def handle_event("save", %{"state" => params}, socket) do
    persist_state(socket.assigns.persistence_type, params, socket)
  end

  @impl true
  def handle_event("cancel_edit",_, socket) do
    {
      :noreply,
      socket
      |> assign_form(State.changeset(%State{}))
      |> assign_persistence_type(:add)
    }
  end

  @impl true
  def handle_event("edit_state", %{"state-id" => state_id}, socket) do
    agent = State.get_state(state_id)
    {
      :noreply,
      socket
      |> assign_persistence_type(:update)
      |> assign_form(State.changeset(agent))
    }
  end

  @impl true
  def handle_event("delete_state", %{"state-id" => state_id}, socket) do
    :ok = State.delete_state(state_id)
    {
      :noreply,
      socket
    }
  end


  defp persist_state(:add, params, socket) do
    case State.add_state(params) do
      {:ok, (%State{} = state)} ->
        {
          :noreply,
          socket
          |> put_flash(:info, "New agent added with ID #{state.id}")
          |> assign_form(State.changeset(%State{}))
          |> assign_persistence_type(:add)
        }

      {:error, %Ecto.Changeset{} = cs} ->
        {
          :noreply,
          socket
          |> assign_form(cs)
        }
    end
  end

  defp persist_state(:update, params, socket) do
    case State.update_state(params) do
      {:ok, (%State{} = _state)} ->
        {
          :noreply,
          socket
          |> assign_form(State.changeset(%State{}))
          |> assign_persistence_type(:add)
        }

      {:error, %Ecto.Changeset{} = cs} ->
        {
          :noreply,
          socket
          |> assign_form(cs)
        }
    end
  end

  @impl true
  def handle_info(
    %{
      event: "agent:started",
      payload: %{id: new_agent_id, pid: pid}
    },
    socket
  ) do
    node = if is_pid(pid), do: node(pid), else: nil

    {
      :noreply,
      socket
      |> stream_insert(:agent_list, %{id: new_agent_id, pid: pid, node: node}, at: 0)
    }
  end

  @impl true
  def handle_info(
    %{
      event: "agent:stopped",
      payload: %{id: stopped_agent_id}
    },
    socket
  ) do
    {
      :noreply,
      socket
      |> stream_delete(:agent_list,%{id: stopped_agent_id})
    }
  end


  @impl true
  def handle_info({:nodeup, node_id}, socket) do
    node_list = [node_id | socket.assigns.cluster_nodes]

    {
      :noreply,
      socket
      |> assign(:cluster_nodes, node_list)
    }
  end

  @impl true
  def handle_info({:nodedown, node_id}, socket) do
    node_list = List.delete(socket.assigns.cluster_nodes, node_id)
    {
      :noreply,
      socket
      |> assign(:cluster_nodes, node_list)
    }
  end

  @impl true
  def handle_info(msg, socket) do
    IO.inspect(msg)
    {:noreply, socket}
  end

  # Function component helpers for the view
  def editor_title(%{persistence_type: :add} = assigns),
    do: ~H|<h2 class="font-bold text-blue-700">Define A New Stateful Object</h2>|

  def editor_title(%{persistence_type: :update} = assigns),
    do: ~H|<h2 class="font-bold text-blue-700">Updating Stateful Object</h2>|

end
