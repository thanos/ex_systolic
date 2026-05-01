# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
