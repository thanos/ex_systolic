defmodule ExSystolic.Trace do
  @moduledoc """
  Execution trace recording for systolic array runs.

  Every tick optionally emits a `Trace.Event` per PE, recording inputs,
  outputs, and state transitions.  The trace is:

  - **optional** -- disabled by default to avoid overhead
  - **complete** -- when enabled, every PE at every tick is recorded
  - **deterministic** -- same inputs always produce the same trace

  ## Storage and ordering

  Internally, events are stored in **reverse-chronological order**
  (newest event first) so that recording is O(1) amortized.  The query
  helpers `at/2` and `for_coord/2` return their results in
  **chronological order** (oldest first), matching the order in which
  events were recorded.  If you access `trace.events` directly, call
  `Enum.reverse/1` to obtain chronological order.

  ## Use cases

  - Debugging PE behaviour
  - Visualising data flow (e.g. in a livebook)
  - Regression testing (compare traces across runs)
  """

  defmodule Event do
    @moduledoc """
    A single trace event: the record of one PE step at one tick.

    ## Fields

    - `:tick` -- the tick at which the PE was executed (0-based)
    - `:coord` -- the PE coordinate
    - `:inputs` -- map of port_name => input value (or `:empty`)
    - `:outputs` -- map of port_name => output value
    - `:state_before` -- the PE state before this tick
    - `:state_after` -- the PE state after this tick

    ## Examples

        iex> e = %ExSystolic.Trace.Event{
        ...>   tick: 0, coord: {0, 0},
        ...>   inputs: %{west: 3, north: 4},
        ...>   outputs: %{result: 12, east: 3, south: 4},
        ...>   state_before: 0, state_after: 12
        ...> }
        iex> e.state_after
        12
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

  @type event :: Event.t()

  defstruct events: []

  @type t :: %__MODULE__{events: [event()]}

  @doc """
  Creates a new trace from a list of events.

  ## Examples

      iex> trace = ExSystolic.Trace.new([])
      iex> trace.events
      []

  """
  @spec new([event()]) :: t()
  def new(events \\ []) do
    %__MODULE__{events: events}
  end

  @doc """
  Records a single PE step as a trace event.

  Events are prepended for O(1) amortized recording.  Use `at/2` or
  `for_coord/2` to retrieve in chronological order.

  ## Examples

      iex> trace = ExSystolic.Trace.new()
      iex> event = %ExSystolic.Trace.Event{tick: 0, coord: {0,0}, inputs: %{}, outputs: %{}, state_before: 0, state_after: 7}
      iex> trace2 = ExSystolic.Trace.record(trace, event)
      iex> hd(trace2.events).state_after
      7
      iex> hd(trace2.events).tick
      0

  """
  @spec record(t(), event()) :: t()
  def record(%__MODULE__{events: events} = trace, event) do
    # Prepend for O(1) amortized appends; callers that care about
    # chronological order can reverse.
    %__MODULE__{trace | events: [event | events]}
  end

  @doc """
  Filters trace events by tick number, returned in chronological order.

  ## Examples

      iex> e0 = %ExSystolic.Trace.Event{tick: 0, coord: {0,0}, inputs: %{}, outputs: %{}, state_before: 0, state_after: 0}
      iex> e1 = %ExSystolic.Trace.Event{tick: 1, coord: {0,0}, inputs: %{}, outputs: %{}, state_before: 0, state_after: 0}
      iex> trace = ExSystolic.Trace.new() |> ExSystolic.Trace.record(e0) |> ExSystolic.Trace.record(e1)
      iex> [event] = ExSystolic.Trace.at(trace, 0)
      iex> event.tick
      0

  """
  @spec at(t(), non_neg_integer()) :: [event()]
  def at(%__MODULE__{events: events}, tick) do
    events
    |> Enum.filter(&(&1.tick == tick))
    |> Enum.reverse()
  end

  @doc """
  Filters trace events by PE coordinate, returned in chronological order.

  ## Examples

      iex> e0 = %ExSystolic.Trace.Event{tick: 0, coord: {0,0}, inputs: %{}, outputs: %{}, state_before: 0, state_after: 0}
      iex> e1 = %ExSystolic.Trace.Event{tick: 1, coord: {0,0}, inputs: %{}, outputs: %{}, state_before: 0, state_after: 0}
      iex> trace = ExSystolic.Trace.new() |> ExSystolic.Trace.record(e0) |> ExSystolic.Trace.record(e1)
      iex> ticks = ExSystolic.Trace.for_coord(trace, {0,0}) |> Enum.map(& &1.tick)
      iex> ticks
      [0, 1]

  """
  @spec for_coord(t(), ExSystolic.Grid.coord()) :: [event()]
  def for_coord(%__MODULE__{events: events}, coord) do
    events
    |> Enum.filter(&(&1.coord == coord))
    |> Enum.reverse()
  end
end
