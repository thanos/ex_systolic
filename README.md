# ExSystolic

A BEAM-native systolic array simulator -- a **clocked spatial dataflow simulator** with explicit time (ticks), explicit data movement (links), and local processing elements (PEs).

[![Hex.pm](https://img.shields.io/hexpm/v/ex_systolic.svg)](https://hex.pm/packages/ex_systolic)
[![Hex.pm](https://img.shields.io/hexpm/dt/ex_systolic.svg)](https://hex.pm/packages/ex_systolic)
[![Hex.pm](https://img.shields.io/hexpm/l/ex_systolic.svg)](https://hex.pm/packages/ex_systolic)
[![HexDocs.pm](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/ex_systolic)
[![Coverage Status](https://coveralls.io/repos/github/thanos/ex_systolic/badge.svg?branch=main)](https://coveralls.io/github/thanos/ex_systolic?branch=main)

This is not a spreadsheet engine, a DAG executor, or a reactive system. This is a systolic array: data pulses through a grid of simple processors in a regular rhythm, like blood through a heart.

---


## Tutorial: What Is a Systolic Array?

### The Idea

A **systolic array** is a grid of processing elements (PEs) connected by communication channels called **links**. The name comes from the analogy with a heartbeat: data pulses through the array one **tick** at a time, in a regular, predictable rhythm.

Every PE executes the same simple operation every tick. Data arrives from neighbours, is processed, and is forwarded onward. There is no global state, no shared memory, and no coordination beyond the clock.

This makes systolic arrays:

- **Deterministic** -- same inputs always produce same outputs
- **Predictable** -- execution time is known in advance
- **Composable** -- the same PE tiles across arbitrarily large grids

### Why Systolic?

Many algorithms decompose into a repetitive local operation applied across a spatial layout. Matrix multiplication is the canonical example: each output element is the dot product of a row and a column, and the multiply-accumulate operation is the same everywhere.

### Tick Semantics

Every tick, each PE:

1. **Reads** its inputs (from neighbour links, produced by the previous tick)
2. **Computes** a pure function of its state + inputs
3. **Writes** outputs (to neighbour links, consumed by the next tick)

The clock enforces a strict read-before-write order across the entire array. No PE ever reads data produced in the same tick. This is the fundamental correctness guarantee.

### The MAC Processing Element

The multiply-accumulate (MAC) PE is the classic systolic PE (Kung & Leiserson, 1979):

```
inputs:  west -> a, north -> b
state:   acc (accumulator)
outputs: east -> a, south -> b, result -> acc
```

The PE multiplies its two inputs, adds the product to the accumulator, and forwards both inputs unchanged. The accumulator at PE (i, j) after k ticks of real data holds:

```
C[i][j] = A[i][0]*B[0][j] + A[i][1]*B[1][j] + ... + A[i][k-1]*B[k-1][j]
```

which is exactly the (i, j) entry of the matrix product C = A * B.

### Stream Skewing

For systolic GEMM, the input streams must be **skewed** so data arrives at each PE at the right tick:

- Row i of A is delayed by i leading zeros before entering the west boundary at PE (i, 0)
- Column j of B is delayed by j leading zeros before entering the north boundary at PE (0, j)

This ensures that element A[i][k] and element B[k][j] arrive at PE (i, j) simultaneously. Without skewing, the data wavefronts would be misaligned and PEs would compute incorrect partial sums.

### Links

A link is a directed FIFO buffer connecting an output port of one PE to an input port of another. With the default latency-1, a value written at tick T is readable at tick T+1. The strict read-then-write order ensures a value is always consumed before the same link is written to again.

### The GraphBLAS Connection

GraphBLAS defines graph algorithms in terms of linear algebra over **semi-rings**. The standard arithmetic semi-ring `(multiply: *, add: +)` gives classical matrix multiplication. Other semi-rings give different algorithms:

| Semi-ring | Multiply | Add | Application |
|-----------|----------|-----|-------------|
| Arithmetic | `*` | `+` | Matrix multiply |
| Boolean | `AND` | `OR` | Reachability |
| Tropical | `+` | `min` | Shortest paths |
| Counting | `*` | `+` | Path counting |

The ex_systolic PE behaviour is designed to support any semi-ring: future phases can implement PEs that accept semi-ring operations as parameters, without changing the array, clock, or link infrastructure.

### Determinism

The entire execution is deterministic because:

1. All data structures are immutable
2. The tick order (inject, read, execute, write, record) is fixed
3. PE step functions are pure
4. No concurrency, no random scheduling, no IO during execution

Given the same array configuration and input streams, `Clock.run` always produces the same result. This is a design requirement, not an accident.

---

## Quick Start

Add `ex_systolic` to your dependencies:

```elixir
def deps do
  [
    {:ex_systolic, "~> 0.1.0"}
  ]
end
```

Then:

```elixir
alias ExSystolic.{Array, Clock, PE.MAC}

array =
  Array.new(rows: 2, cols: 2)
  |> Array.fill(MAC)
  |> Array.connect(:west_to_east)
  |> Array.connect(:north_to_south)
  |> Array.input(:west, [{{0, 0}, [1, 2]}, {{1, 0}, [3, 4]}])
  |> Array.input(:north, [{{0, 0}, [5, 7]}, {{0, 1}, [6, 8]}])

result = Clock.run(array, ticks: 5)
```

---

## Simple Example: 2x2 Matrix Multiplication

The `ExSystolic.Examples.GEMM` module provides a ready-made systolic GEMM:

```elixir
iex> alias ExSystolic.Examples.GEMM
iex> A = [[1, 2], [3, 4]]
iex> B = [[5, 6], [7, 8]]
iex> GEMM.run(A, B)
[[19, 22], [43, 50]]
```

Hand-checking: C[1][1] = 3*6 + 4*8 = 18 + 32 = 50.

---

## Real-World Example: Image Convolution with a Systolic Array

Convolution is a fundamental operation in image processing and neural networks. A 2D convolution applies a small kernel (filter) across an image -- this maps directly to a systolic array where each PE accumulates one pixel of the output.

Consider a 3x3 Sobel edge-detection kernel applied to a grayscale image. Each output pixel is the sum of element-wise products between the kernel and a 3x3 patch of the image.

```elixir
defmodule SobelPE do
  @behaviour ExSystolic.PE

  @impl true
  def init(opts), do: Keyword.get(opts, :kernel_row, [])

  @impl true
  def step(kernel_row, inputs, _tick, _context) do
    pixel = Map.get(inputs, :north, 0)
    pixel_val = if pixel == :empty, do: 0, else: pixel

    partial = Enum.zip(kernel_row, pixel_val)
    |> Enum.map(fn {k, p} -> k * p end)
    |> Enum.sum()

    outputs = %{south: pixel, partial: partial}
    {kernel_row, outputs}
  end
end

# Build a systolic array that streams image rows through PEs
# Each PE holds one row of the 3x3 kernel and computes partial products
alias ExSystolic.{Array, Clock}

kernel = [
  [-1, 0, 1],
  [-2, 0, 2],
  [-1, 0, 1]
]

# Create one PE per kernel row, connected vertically
array =
  Array.new(rows: 3, cols: 1)
  |> Array.fill(SobelPE, %{
    {0, 0} => [kernel_row: Enum.at(kernel, 0)],
    {1, 0} => [kernel_row: Enum.at(kernel, 1)],
    {2, 0} => [kernel_row: Enum.at(kernel, 2)]
  })
  |> Array.connect(:north_to_south)
  |> Array.input(:north, [{{0, 0}, image_row_stream}])

result = Clock.run(array, ticks: image_width + 3)
```

This pattern -- streaming data through PEs that each hold part of a kernel -- generalises to any sliding-window computation: blurring, sharpening, gradient computation, and even 1D convolutions in sequence models.

---

## Real-World Example: Shortest Paths (Tropical Semi-ring)

The tropical semi-ring `(multiply: +, add: min)` turns matrix multiplication into shortest-path computation. Given an adjacency matrix D where D[i][j] is the edge weight from node i to node j, the matrix product under the tropical semi-ring gives the shortest 2-hop paths. Repeated squaring gives all-pairs shortest paths.

```elixir
defmodule TropicalMAC do
  @behaviour ExSystolic.PE

  @impl true
  def init(_opts), do: :infinity

  @impl true
  def step(acc, inputs, _tick, _context) do
    a = Map.get(inputs, :west)
    b = Map.get(inputs, :north)

    a_val = if is_nil(a) or a == :empty, do: :infinity, else: a
    b_val = if is_nil(b) or b == :empty, do: :infinity, else: b

    product = if a_val == :infinity or b_val == :infinity do
      :infinity
    else
      a_val + b_val
    end

    new_acc = min(acc, product)

    outputs = %{result: new_acc}
    outputs = if not is_nil(a) and a != :empty, do: Map.put(outputs, :east, a), else: outputs
    outputs = if not is_nil(b) and b != :empty, do: Map.put(outputs, :south, b), else: outputs

    {new_acc, outputs}
  end
end

# Compute all-pairs shortest paths via repeated squaring
# adjacency_matrix[i][j] = edge weight, or :infinity if no edge
alias ExSystolic.{Array, Clock, Examples.GEMM}

n = length(adjacency_matrix)
ticks = 3 * n - 1

array =
  Array.new(rows: n, cols: n)
  |> Array.fill(TropicalMAC)
  |> Array.connect(:west_to_east)
  |> Array.connect(:north_to_south)
  |> Array.input(:west, GEMM.west_streams(adjacency_matrix, n, n, n))
  |> Array.input(:north, GEMM.north_streams(adjacency_matrix, n, n, n))

# One round gives 2-hop shortest paths
result = Clock.run(array, ticks: ticks)
two_hop_distances = Array.result_matrix(result)
```

This demonstrates how swapping the semi-ring operations transforms the same systolic architecture from matrix multiplication into graph algorithms -- the core insight behind GraphBLAS.

---

## Architecture

```
                  north boundary
                       |
                       v
    west boundary -> [ PE ] --east--> [ PE ] --east--> ...
                       |               |
                      south           south
                       |               |
                       v               v
                     [ PE ] --east--> [ PE ] --east--> ...
                       .               .
                       .               .
```

Each PE is a pure state machine. Each link is a FIFO buffer. The clock drives execution tick by tick in a strict order:

1. **INJECT** external inputs into boundary links
2. **READ** all link buffers (consuming values from the previous tick)
3. **EXECUTE** all PE step functions
4. **WRITE** PE outputs into link buffers (for the next tick)
5. **RECORD** trace events (if tracing is enabled)

### Module Map

| Module | Role |
|--------|------|
| `ExSystolic.Grid` | Coordinate geometry and neighbour lookups |
| `ExSystolic.Link` | FIFO communication channels between PE ports |
| `ExSystolic.PE` | Behaviour for processing elements |
| `ExSystolic.PE.MAC` | Multiply-accumulate PE |
| `ExSystolic.Array` | Array construction: fill, connect, input |
| `ExSystolic.Clock` | Tick-by-tick execution driver |
| `ExSystolic.Trace` | Optional execution trace recording |
| `ExSystolic.Backend.Interpreted` | Single-process reference backend |
| `ExSystolic.Examples.GEMM` | General matrix multiply |

---

## Tracing

Enable tracing to inspect every PE step at every tick:

```elixir
array =
  Array.new(rows: 2, cols: 2)
  |> Array.fill(MAC)
  |> Array.connect(:west_to_east)
  |> Array.connect(:north_to_south)
  |> Array.input(:west, ...)
  |> Array.input(:north, ...)
  |> Array.trace(true)

result = Clock.run(array, ticks: 5)

for event <- result.trace.events do
  IO.puts("Tick #{event.tick} PE#{inspect(event.coord)}: " <>
    "inputs=#{inspect(event.inputs)} " <>
    "#{event.state_before} -> #{event.state_after}")
end
```

---

## Custom Processing Elements

Any module implementing the `ExSystolic.PE` behaviour can be used as a PE:

```elixir
defmodule MyPE do
  @behaviour ExSystolic.PE

  @impl true
  def init(opts), do: Keyword.get(opts, :initial, 0)

  @impl true
  def step(state, inputs, tick, context) do
    # Pure function: state + inputs -> {new_state, outputs}
    {new_state, %{result: new_state, east: Map.get(inputs, :west)}}
  end
end

array =
  Array.new(rows: 2, cols: 2)
  |> Array.fill(MyPE)
  |> Array.connect(:west_to_east)
```

The PE does not know where it is in the array (the `context` map provides `coord` but the PE may ignore it), what its neighbours are doing, or what other PEs exist. This locality is what makes systolic arrays scale.

---

## Roadmap

### Phase 1: Interpreted Backend (current)

- Single BEAM process, fully deterministic
- MAC PE, GEMM example, trace recording
- 95%+ test coverage, property-based testing

### Phase 2: Semi-ring Abstraction

- Extract `*` and `+` from the MAC PE into a configurable semi-ring module
- Boolean semi-ring (AND/OR) for reachability
- Tropical semi-ring (+/min) for shortest paths
- Custom semi-rings via user-defined modules

### Phase 3: Sparse Data & GraphBLAS Compliance

- Zero-skipping: PEs skip ticks when inputs are empty
- Sparse matrix representations
- Compressed sparse column/row input streams
- GraphBLAS-compatible API surface

### Phase 4: Alternative Backends

- Multi-process backend with per-PE GenServers
- Native backend via NIF for performance-critical paths
- GPU backend via Nx/XLA for large arrays
- Streaming trace sink (file, ETS, or process)

### Phase 5: Tooling & Visualisation

- Livebook integration with animated tick visualisation
- ASCII/Unicode grid renderer for terminal output
- Performance benchmarks vs. naive matrix multiply
- Heatmap rendering of PE state over time

---

## References

### Foundational Papers

- **H. T. Kung and C. E. Leiserson**, "Systolic Arrays (for VLSI)," in *Sparse Matrix Proceedings*, 1979. -- The original systolic array paper.
- **H. T. Kung**, "Why Systolic Architectures?," *IEEE Computer*, 1982. -- The motivation and design philosophy.

### GraphBLAS

- **J. Kepner et al.**, "Mathematical Foundations of the GraphBLAS," *IEEE HPEC*, 2016. -- The mathematical specification.
- **T. Mattson et al.**, "The GraphBLAS C API Specification," 2017. -- The C API that defines the standard.
- [GraphBLAS.org](https://graphblas.org) -- The official GraphBLAS resource page.

### Systolic Arrays in Practice

- **S. V. Rajopadhye**, "Systolic Arrays," in *Encyclopedia of Parallel Computing*, 2011. -- Comprehensive survey.
- **Google TPU** -- The Tensor Processing Unit uses a large systolic array for matrix multiplication in production ML workloads. See: N. P. Jouppi et al., "In-Datacenter Performance Analysis of a Tensor Processing Unit," *ISCA*, 2017.

### Elixir & BEAM

- **J. Armstrong**, "Making Reliable Distributed Systems in the Presence of Software Errors," 2003. -- The Erlang/OTP design philosophy that inspires ex_systolic's emphasis on correctness over raw speed.
- [The Elixir School of Stream Data](https://elixirschool.com/blog/using-streamdata-for-property-based-testing/) -- Property-based testing with StreamData, which ex_systolic uses extensively.

---

## Installation

```elixir
def deps do
  [
    {:ex_systolic, "~> 0.1.0"}
  ]
end
```

Documentation can be found at [https://hexdocs.pm/ex_systolic](https://hexdocs.pm/ex_systolic).

---

## License

Apache 2.0 -- see [LICENSE](LICENSE) for details.
