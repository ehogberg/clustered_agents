defmodule ClusteredAgents.State do
  defstruct [:id, :description, :value, :updated_at]

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

    Agent.start_link(fn -> s end, name: name)
  end

  def list_states(),
    do: DynamicSupervisor.which_children(ClusteredAgents.StateSupervisor)

  def add_state(state) do
    {:ok, _} = DynamicSupervisor.start_child(
      ClusteredAgents.StateSupervisor,
      {__MODULE__,state}
    )

    {:ok, get_state(state.id)}
  end

  def update_state(%__MODULE__{} = attrs) do
    Agent.update(
      state_name(attrs.id),
      fn _ -> %{ attrs | updated_at: DateTime.utc_now()} end
    )
  end

  def delete_state(id) do
    pid = id
    |> pid_for_state()
    |> List.first()
    |> elem(0)

    DynamicSupervisor.terminate_child(
      ClusteredAgents.StateSupervisor,
      pid
    )
  end

  def get_state(id), do: Agent.get(state_name(id), & &1)

  def pid_for_state(id),
    do: Registry.lookup(ClusteredAgents.Registry, id)

  defp state_name(id),
    do: {:via, Registry, {ClusteredAgents.Registry, id}}
end
