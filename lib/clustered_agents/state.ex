defmodule ClusteredAgents.State do
  use Agent

  alias Ecto.Changeset
  alias ClusteredAgentsWeb.Endpoint
  use Ecto.Schema
  use Retry.Annotation
  require Logger

  embedded_schema do
    field(:description, :string)
    field(:value, :integer)
    field(:updated_at, :utc_datetime)
  end

  def start_link(%__MODULE__{} = state) do
    s = %__MODULE__{
      id: state.id,
      value: state.value,
      description: state.description,
      updated_at: DateTime.utc_now(:millisecond)
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

      err ->
        err
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
    do:
      Horde.Registry.select(
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

    cs = changeset(%__MODULE__{}, attrs)

    with {:ok, state} <- Ecto.Changeset.apply_action(cs, :validate),
         {:ok, _pid} <-
           Horde.DynamicSupervisor.start_child(
             ClusteredAgents.StateSupervisor,
             {__MODULE__, state}
           ) do
      {:ok, get_state(attrs["id"])}
    end
  end

  def update_state(%__MODULE__{} = state, attrs) do
    with :ok <- check_for_stale_agent_data(state),
         %Ecto.Changeset{} = cs <- changeset(state, attrs),
         {:ok, updated_state} <- Ecto.Changeset.apply_action(cs, :validate),
         :ok <- delete_state(state.id),
         {:ok, _pid} <-
           Horde.DynamicSupervisor.start_child(
             ClusteredAgents.StateSupervisor,
             {__MODULE__, updated_state}
           ) do
      {:ok, get_state(updated_state.id)}
    end
  end

  defp check_for_stale_agent_data(state)
       when is_binary(state.id) do
    existing_agent = get_state(state.id)

    if DateTime.compare(existing_agent.updated_at, state.updated_at) == :eq do
      :ok
    else
      {
        :error,
        {
          :stale_agent_data,
          state.id,
          state.updated_at,
          existing_agent.updated_at
        }
      }
    end
  end

  def delete_state(id) when is_binary(id) do
    pid =
      id
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

  @doc """
  Retrieves the current state of a specified agent.

  Reading the current value of a stateful object must support a retry scenario:
  the case where a object is being relocated elsewhere in the cluster but the
  registry has not yet been updated to specify the new pid; in this case,
  attempting to read the old pid will return a process exit and raise.  We catch
  that here and support a reasonable number of retry attempts to allow the
  registry to catch up to the rebalanced object.
  """
  @retry with: exponential_backoff() |> cap(1_000) |> Stream.take(10)
  def get_state(id) do
    try do
      Agent.get(state_name(id), & &1)
    catch
      :exit, e ->
        Logger.debug("Expired/invalid agent process for ID #{id}; re-reading")
        {:error, e}
    end
  end

  def pid_for_state(id),
    do: Horde.Registry.lookup(ClusteredAgents.Registry, id)

  defp state_name(id) when is_binary(id),
    do: {:via, Horde.Registry, {ClusteredAgents.Registry, id}}
end
