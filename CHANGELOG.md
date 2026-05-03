# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2025-05-03

### Added

- `ExSystolic.Backend.Partitioned` -- tile-based parallel backend using `Task.Supervisor` (default) or `Poolex` worker pool (`dispatch: :pool`)
- `ExSystolic.Backend.PoolexWorker` -- GenServer worker for Poolex-based dispatch
- `ExSystolic.Backend.LinkOps` -- shared link buffer operations (`inject_streams/2`, `drain_links/2`, `write_pe_outputs/2`), eliminating triple-duplicated code across Clock, Interpreted, and Partitioned
- `ExSystolic.Tile` -- tile data structure for partitioned execution with documented invariants
- `ExSystolic.TilePartitioner` -- splits arrays into rectangular tiles with validation (`tile_rows > 0`, `tile_cols > 0`)
- `ExSystolic.Application` -- supervision tree with `ExSystolic.TaskSupervisor` and `:systolic_pool` Poolex pool
- `ExSystolic.Backend` behaviour -- documents the 6-step BSP tick contract (INJECT, READ, EXECUTE, COLLECT, WRITE, RECORD)
- `Space.links/2` callback -- Space modules now produce boundary + internal links for a given direction; `Grid2D` implements it `:west_to_east` and `:north_to_south`
- `Array.result_map/1` -- returns `coord => state` for any Space implementation
- `PE.value/2` and `PE.present?/2` -- helpers for handling `:empty` / `nil` PE inputs idiomatically
- `Array.input/3` -- accepts any atom port (not just `:west`/`:north`); raises `ArgumentError` on duplicate `{coord, port}` keys
- Architecture diagram in `ExSystolic` moduledoc showing BSP dataflow
- Determinism contract in `PE` moduledoc forbidding side effects (Process, Agent, ETS, IO, timers)
- `:empty` documented as reserved atom in `Link` and `PE` moduledocs
- Backend conformance test (`test/ex_systolic/backend/conformance_test.exs`) -- result parity and trace parity across backends
- Cross-backend trace parity test (sorted `{tick, coord, state_before, state_after}` comparison)
- Link FIFO interleaved property test
- Capacity > 1 link tests (multiple writes, FIFO order, `:full` on overflow)
- Poolex pool dispatch test (`dispatch: :pool` parity with interpreted)
- Application supervision tests (TaskSupervisor alive, Poolex pool accepts calls)
- Custom space end-to-end execution test through Clock
- Full PE state parity test beyond `result_matrix`
- Doctest directives in 6 test files (34 doctests, up from 12)

### Changed

- `Array.connect/2` delegates to `Space.links/2`; Grid2D-specific link functions removed from `array.ex`
- `Array.result_matrix/1` raises `ArgumentError` for non-Grid2D spaces (was silently producing nil cells)
- `Partitioned` backend uses `Task.Supervisor.async_stream` with `ordered: true` and `timeout: :infinity`; trace events sorted by `{tick, coord}` after collection
- `Partitioned` accepts `dispatch: :tasks | :pool` option (default `:tasks`)
- `Clock.run/2` raises `ArgumentError` for unknown backends (was `CaseClauseError`)
- `Clock.step/1` uses `LinkOps` helpers instead of inline link operations
- `Interpreted.write_outputs/3` delegates to `LinkOps.write_pe_outputs` + `LinkOps.inject_streams`
- `MAC.step/4` uses `PE.value/2` and `PE.present?/2` instead of inline `:empty` checks
- `Trace.at/2` and `Trace.for_coord/2` return events in chronological order (filter-then-reverse); ordering documented
- `Trace.Event` has a single canonical typespec with `@type event :: Event.t()` convenience alias
- All ranges use `//1` step syntax for Elixir 1.20-rc compatibility (15 occurrences)
- `Link.read/1` typespec changed to `{term() | :empty, t()}`
- `Link.write/2` and `Link.read/1` doctests fixed (bind-then-assert pattern, no bare `_`)
- `Trace.record/2` doctest now verifies event content (`state_after`, `tick`)
- `Link.tick/1` doctest now demonstrates buffer preservation
- `Grid.member?/2` doctest includes negative-coordinate edge case
- `TilePartitioner` moduledoc accurately describes boundary-link handling (excluded from tiles, managed globally)
- `Application` has full `@moduledoc` and `@doc` on `start/2`
- Backend table in `ExSystolic` moduledoc lists all 19 modules

### Removed

- `Interpreted.read_inputs/2` -- dead code that violated buffer drainage contract; tests removed
- `Array.input/3` dead `case direction` branch (identity mapping `:west -> :west`, `:north -> :north`)
- `Application.start/1` dead `Code.ensure_loaded?(Poolex)` conditional (Poolex is always a dependency)
- `Tile.boundary_inputs` field -- dead struct field never read by Partitioned
- Grid2D-specific `build_direction_links` clauses and helper functions from `array.ex` (~90 LOC)

### Fixed

- Trace event ordering was non-deterministic in partitioned backend (`ordered: false` in `Task.async_stream`)
- Link doctests for `write/2` and `read/2` never executed (bare `_` in expected output)
- `result_matrix/1` silently returned nil cells for non-Grid2D spaces
- `Array.input/3` silently overwrote duplicate `{coord, port}` streams
- Range syntax incompatibility with Elixir 1.20-rc (bare `0..(n-1)` where n could be 0)
- `PoolexWorker.handle_call` timeout risk -- callers now pass `:infinity`
- Dialyzer opaque type violation in `TilePartitioner` (`MapSet.member?` replaced with `Map.has_key?`)

### Performance

- `LinkOps.drain_links/2` builds endpoint index map for O(1) lookup (mutation still list-based; see review item 2.1 for full indexed-map refactoring)

### Known Limitations

- Trace.events list grows unbounded (no `max_events` or sampling)
- Link mutation still uses `List.replace_at` (O(n)); indexed map storage not yet implemented
- Latency > 1 links are not yet implemented in the backend
- No sparse data support; every PE executes every tick
- No semi-ring abstraction; MAC hard-codes arithmetic operations

## [0.1.0] - 2025-05-01

### Added

- `ExSystolic.Grid` -- rectangular coordinate geometry with neighbour lookups (north, south, east, west)
- `ExSystolic.Link` -- FIFO communication channels between PE ports with configurable capacity and latency
- `ExSystolic.PE` -- behaviour for processing elements with `init/1` and `step/4` callbacks
- `ExSystolic.PE.MAC` -- multiply-accumulate PE implementing the classic Kung-Leiserson systolic GEMM PE
- `ExSystolic.Array` -- array construction API: `new`, `fill`, `connect`, `input`, `trace`, `result_matrix`
- `ExSystolic.Clock` -- tick-by-tick execution driver with `run/2` and `step/1`
- `ExSystolic.Trace` -- optional execution trace recording with per-tick and per-coordinate querying
- `ExSystolic.Backend.Interpreted` -- single-process reference backend implementing the strict tick order (inject, read, execute, write, record)
- `ExSystolic.Examples.GEMM` -- general matrix multiply using systolic wavefront with skewed input streams
- Tutorial livebook: `notebooks/introduction_to_systolic_arrays.livemd`
- 86 unit tests + 9 property-based tests (95.4% coverage)
- CI pipeline: Elixir 1.18/OTP 27, 1.19/OTP 28, 1.20/OTP 29 (experimental)
- Publish workflow: Hex.pm release on `v*` tag push
- Quality toolchain: credo, dialyxir, excoveralls, stream_data, mix_audit

### Design Principles

- Everything is pure Elixir; no GenServer, no Nx, no NIFs
- Execution is deterministic and reproducible
- All data structures are immutable
- All public functions have `@doc`, typespecs, and doctests

### Known Limitations

- Interpreted backend has no parallelism; large arrays will be slow
- No sparse data support; every PE executes every tick
- Latency > 1 links are not yet implemented in the backend
- Trace is held entirely in memory
- No semi-ring abstraction; MAC hard-codes arithmetic operations

### Performance

No benchmarks have been run. The interpreted backend is chosen for
architectural clarity and correctness, not for speed. Performance
claims will be made only after benchmarks exist.
