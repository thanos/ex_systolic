defmodule ExSystolic.Trace do
  @moduledoc """
  Execution trace recording for systolic array runs.

  Every tick optionally emits a `Trace.Event` per PE, recording inputs,
  outputs, and state transitions.  The trace is:

  - **optional** -- disabled by default to avoid overhead
  - **complete** -- when enabled, every PE at every tick is recorded
  - **deterministic** -- same inputs always produce the same trace

  ## Use cases

  - Debugging PE behaviour
  - Visualising data flow (e.g. in a livebook)
  - Regression testing (compare traces across runs)
  """

  @type event :: %__MODULE__.Event{
          tick: non_neg_integer(),
          coord: ExSystolic.Grid.coord(),
          inputs: map(),
          outputs: map(),
          state_before: term(),
          state_after: term()
        }

  defmodule Event do
    @moduledoc """
    A single trace event: the record of one PE step at one tick.
    """

    @type t :: %__MODULE__{
            tick: non_neg_integer(),
            coord: ExSystolic.Grid.coord(),
            inputs: map(),
            outputs: map(),
            state_before: term(),
            state_after: term()
          }

    @enforce_keys [:tick, :coord, :inputs, :outputs, :state_before, :state_after]
    defstruct [:tick, :coord, :inputs, :outputs, :state_before, :state_after]
  end

  @doc """
  Creates a new trace from a list of events.

  ## Examples

      iex> trace = ExSystolic.Trace.new([])
      iex> trace.events
      []

  """
  @spec new([event()]) :: %{events: [event()]}
  def new(events \\ []) do
    %{events: events}
  end

  @doc """
  Records a single PE step as a trace event and appends it to the trace.

  ## Examples

      iex> trace = ExSystolic.Trace.new()
      iex> event = %ExSystolic.Trace.Event{tick: 0, coord: {0,0}, inputs: %{}, outputs: %{}, state_before: 0, state_after: 0}
      iex> trace2 = ExSystolic.Trace.record(trace, event)
      iex> length(trace2.events)
      1

  """
  @spec record(%{events: [event()]}, event()) :: %{events: [event()]}
  def record(%{events: events} = _trace, event) do
    %{events: events ++ [event]}
  end

  @doc """
  Filters trace events by tick number.

  ## Examples

      iex> e0 = %ExSystolic.Trace.Event{tick: 0, coord: {0,0}, inputs: %{}, outputs: %{}, state_before: 0, state_after: 0}
      iex> e1 = %ExSystolic.Trace.Event{tick: 1, coord: {0,0}, inputs: %{}, outputs: %{}, state_before: 0, state_after: 0}
      iex> trace = ExSystolic.Trace.new([e0, e1])
      iex> ExSystolic.Trace.at(trace, 0) |> length()
      1

  """
  @spec at(%{events: [event()]}, non_neg_integer()) :: [event()]
  def at(%{events: events}, tick) do
    Enum.filter(events, &(&1.tick == tick))
  end

  @doc """
  Filters trace events by PE coordinate.

  ## Examples

      iex> e0 = %ExSystolic.Trace.Event{tick: 0, coord: {0,0}, inputs: %{}, outputs: %{}, state_before: 0, state_after: 0}
      iex> e1 = %ExSystolic.Trace.Event{tick: 0, coord: {1,1}, inputs: %{}, outputs: %{}, state_before: 0, state_after: 0}
      iex> trace = ExSystolic.Trace.new([e0, e1])
      iex> ExSystolic.Trace.for_coord(trace, {0,0}) |> length()
      1

  """
  @spec for_coord(%{events: [event()]}, ExSystolic.Grid.coord()) :: [event()]
  def for_coord(%{events: events}, coord) do
    Enum.filter(events, &(&1.coord == coord))
  end
end
