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
  """

  @type state :: term()
  @type inputs :: %{atom() => term()}
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
end
