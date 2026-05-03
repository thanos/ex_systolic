defmodule ExSystolic.Application do
  @moduledoc """
  OTP application supervisor for ex_systolic.

  Starts the supervision tree at application boot.  The tree currently
  contains:

  - **`Task.Supervisor`** named `ExSystolic.TaskSupervisor` -- supervises
    asynchronous tile-execution tasks spawned by
    `ExSystolic.Backend.Partitioned`.
  - **Poolex pool** named `:systolic_pool` -- pool of stateless
    `ExSystolic.Backend.PoolexWorker` GenServers used by the
    partitioned backend when `pool: true` is selected.

  The pool size and overflow default to `System.schedulers_online()`.

  This module is intended for OTP infrastructure; library users should
  not need to reference it directly.
  """

  use Application

  @doc """
  Starts the application supervision tree.

  Implements the `Application` behaviour.  Returns `{:ok, pid}` on
  success.
  """
  @impl true
  def start(_type, _args) do
    children = [
      {Task.Supervisor, name: ExSystolic.TaskSupervisor},
      {Poolex, pool_config()}
    ]

    opts = [strategy: :one_for_one, name: ExSystolic.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp pool_config do
    [
      pool_id: :systolic_pool,
      worker_module: ExSystolic.Backend.PoolexWorker,
      workers_count: System.schedulers_online(),
      max_overflow: System.schedulers_online()
    ]
  end
end
