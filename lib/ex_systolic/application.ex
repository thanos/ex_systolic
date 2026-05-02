defmodule ExSystolic.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      if Code.ensure_loaded?(Poolex) do
        [{Poolex, pool_config()}]
      else
        []
      end

    opts = [strategy: :one_for_one, name: ExSystolic.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp pool_config do
    [
      name: :systolic_pool,
      worker_module: ExSystolic.Backend.PoolexWorker,
      workers_count: System.schedulers_online(),
      max_overflow: System.schedulers_online()
    ]
  end
end
