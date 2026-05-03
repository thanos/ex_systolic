defmodule ExSystolic.PE do
  @moduledoc """
  Behaviour that every processing element must implement.

  A PE is a pure state machine: given its current state and a map of
  named inputs, it produces a new state and a map of named outputs.
  No side effects, no mutation, no global state.

  ## Design rationale

  Using a behaviour (rather than a callback-on-module-attribute scheme)
  gives the compiler a chance to warn about missing callbacks and makes
  the contract explicit in the type system.  Each PE module is a
  self-contained unit that can be tested in complete isolation.

  ## The two callbacks

  - `init/1` constructs the initial PE state from keyword options.
  - `step/4` advances the PE by one tick, returning updated state
    and outputs.

  ## Determinism contract (HARD)

  PE callbacks **must be pure**.  Determinism is the foundation of the
  whole library.  In particular, the following are forbidden inside
  `init/1` and `step/4`:

  - **Process operations:** `send/2`, `spawn/1`,
    `GenServer.call/2`, `Agent.update/2`, etc.
  - **ETS / persistent storage:** `:ets.insert/2`, `:dets.*`, file I/O.
  - **Timers and clocks:** `:os.timestamp/0`, `Process.sleep/1`,
    `:timer.*`.
  - **External I/O:** `IO.puts/1`, network calls, port communication.
  - **Random:** any non-seeded RNG (`:rand.uniform/0`, `:crypto.strong_rand_bytes/1`).

  Violating these rules will silently break determinism and trace
  reproducibility.  If a PE needs randomness, take a seed via `init/1`
  options and use `:rand.uniform_s/1` against an explicit state passed
  through PE state.

  ## Reserved input value

  The atom `:empty` is **reserved** to denote "no value present" on an
  input port (typically because the corresponding link buffer was empty
  this tick).  PEs must treat `:empty` as "absent input"; do not return
  `:empty` as a meaningful payload.  See `ExSystolic.PE.value/2` for a
  helper that coerces `:empty`/`nil` to a default value.
  """

  @type state :: term()
  @type inputs :: %{atom() => term() | :empty}
  @type outputs :: %{atom() => term()}
  @type context :: %{atom() => term()}

  @doc """
  Initializes PE state from the given options.
  """
  @callback init(opts :: keyword()) :: state()

  @doc """
  Executes one tick of the PE.

  - `state`   -- current PE state
  - `inputs`  -- map of port_name => value received this tick
  - `tick`    -- current tick number (0-based)
  - `context` -- additional context (e.g. coordinate)

  Returns `{new_state, outputs}` where `outputs` is a map of
  port_name => value to send this tick.
  """
  @callback step(state(), inputs(), tick :: non_neg_integer(), context()) ::
              {state(), outputs()}

  @doc """
  Coerces an absent or empty input to a default value.

  Returns `default` when `value` is either `nil` (port missing from
  the inputs map) or `:empty` (the reserved empty-buffer marker).
  Otherwise returns `value` unchanged.

  ## Examples

      iex> ExSystolic.PE.value(:empty, 0)
      0

      iex> ExSystolic.PE.value(nil, 0)
      0

      iex> ExSystolic.PE.value(7, 0)
      7

      iex> ExSystolic.PE.value(0, 99)
      0

  """
  @spec value(term() | :empty | nil, term()) :: term()
  def value(:empty, default), do: default
  def value(nil, default), do: default
  def value(value, _default), do: value

  @doc """
  Returns true when an input value is "present" (neither `nil` nor
  `:empty`).

  ## Examples

      iex> ExSystolic.PE.present?(:empty)
      false

      iex> ExSystolic.PE.present?(nil)
      false

      iex> ExSystolic.PE.present?(0)
      true

      iex> ExSystolic.PE.present?(false)
      true

  """
  @spec present?(term() | :empty | nil) :: boolean()
  def present?(:empty), do: false
  def present?(nil), do: false
  def present?(_), do: true
end
