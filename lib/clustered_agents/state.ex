defmodule ClusteredAgents.State do
  alias Ecto.Changeset
  alias ClusteredAgentsWeb.Endpoint
  use Ecto.Schema

  embedded_schema do
    field :description, :string
    field :value, :integer
    field :updated_at, :utc_datetime
  end

  def child_spec(%__MODULE__{} = state) do
    %{
      id: state.id,
      start: {__MODULE__, :start_link, [state]},
      restart: :transient
    }
  end

  def start_link(%__MODULE__{} = state) do
    s = %__MODULE__{
      id:  state.id,
      value: state.value,
      description: state.description,
      updated_at: DateTime.utc_now()
    }

    name = state_name(state.id)

    case Agent.start_link(fn -> s end, name: name) do
      {:ok, pid} ->
        ClusteredAgentsWeb.Endpoint.broadcast(
          "agents",
          "agent:started",
          %{id: state.id, pid: pid}
        )

        {:ok, pid}

      err -> err
    end
  end


  def changeset(%__MODULE__{} = state, attrs \\ %{}) do
    state
    |> Changeset.cast(attrs, [:id, :description, :value, :updated_at])
    |> Changeset.validate_required([:value, :description])
    |> Changeset.validate_number(:value, greater_than: 1)
  end

  # Start context-like functions here
  def list_states(),
    do: Horde.DynamicSupervisor.which_children(ClusteredAgents.StateSupervisor)


  def state_ids(),
    do: Horde.Registry.select(
      ClusteredAgents.Registry,
      [
        {
          {:"$1", :"$2", :_},
          [],
          [{{:"$1", :"$2"}}]
        }
      ]
    )

  def add_state(attrs) do
    attrs =
      attrs
      |> Map.put_new("id", Ecto.UUID.generate())
      |> Map.put("updated_at", DateTime.utc_now())

    cs = changeset(%__MODULE__{}, attrs)

    with  {:ok, state} <- Ecto.Changeset.apply_action(cs, :validate),
          {:ok, _pid} <- Horde.DynamicSupervisor.start_child(
        ClusteredAgents.StateSupervisor,
        {__MODULE__, state}
      ) do
        {:ok, state}
    end
  end

  def update_state(%__MODULE__{} = attrs) do
    with  :ok <- check_for_stale_agent_data(attrs),
          :ok <- delete_state(attrs.id),
          {:ok, state} <- add_state(attrs) do
            {:ok, state}
    end
  end

  defp check_for_stale_agent_data(attrs)
    when is_binary(attrs.id) do
    existing_agent = get_state(attrs.id)
    if existing_agent.updated_at == attrs.updated_at do
      :ok
    else
      {
        :error,
        {
          :stale_agent_data,
          attrs.id,
          attrs.updated_at,
          existing_agent.updated_at
        }
      }
    end
  end

  def delete_state(id) when is_binary(id) do
    pid = id
    |> pid_for_state()
    |> List.first()
    |> elem(0)

    Horde.DynamicSupervisor.terminate_child(
      ClusteredAgents.StateSupervisor,
      pid
    )

    Endpoint.broadcast(
      "agents",
      "agent:stopped",
      %{id: id, pid: pid}
    )
  end

  def get_state(pid) when is_pid(pid) do
    Agent.get(pid, & &1)
  end

  def get_state(id), do: Agent.get(state_name(id), & &1)

  def pid_for_state(id),
    do: Horde.Registry.lookup(ClusteredAgents.Registry, id)

  defp state_name(id) when is_binary(id),
    do: {:via, Horde.Registry, {ClusteredAgents.Registry, id}}
end
