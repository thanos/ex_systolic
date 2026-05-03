defmodule ExSystolic.Backend.PoolexWorker do
  @moduledoc """
  A stateless GenServer worker for the Poolex worker pool.

  Workers do not own tile state across ticks.  Each invocation receives
  a work request and returns the result.  This design keeps workers
  stateless and the execution deterministic.

  ## Usage

  Workers are managed by the application supervisor, which
  starts a Poolex pool named `:systolic_pool` at application boot.  The
  pool size defaults to `System.schedulers_online()`.

  You should not need to call this module directly; the
  `ExSystolic.Backend.Partitioned` module dispatches work to the pool
  when run with `dispatch: :pool`.

  ## Timeout policy

  The worker `handle_call/3` callback delegates to a pure function and
  returns immediately on completion.  However, callers using
  `GenServer.call/2` against a worker should pass `:infinity` (or a
  generous explicit timeout) for two reasons:

  1. Tile execution time is data-dependent (PE count, payload size).
     A small default like 5000 ms can cause spurious `:timeout` exits
     under load.
  2. Pool checkout (separate from the call) is itself synchronous; the
     caller controls overall responsiveness via the `checkout_timeout`
     run option.

  `ExSystolic.Backend.Partitioned` always passes `:infinity`.
  """

  use GenServer

  alias ExSystolic.Backend.Interpreted

  @doc """
  Starts a linked worker process.  Required by Poolex.
  """
  @spec start_link() :: GenServer.on_start()
  def start_link do
    GenServer.start_link(__MODULE__, nil)
  end

  @doc false
  @impl true
  def init(_args), do: {:ok, nil}

  @doc """
  Executes a tile's PE step.  Delegates to
  `Interpreted.execute_tick/4`.

  This function is called via `GenServer.call/2` from the partitioned
  backend.  It is a pure function: the same inputs always produce the
  same outputs.
  """
  @impl true
  def handle_call({:run_tile, pes, inputs_map, tick, trace_enabled}, _from, state) do
    result = Interpreted.execute_tick(pes, inputs_map, tick, trace_enabled)
    {:reply, result, state}
  end
end
