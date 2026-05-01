defmodule ExSystolic.Link do
  @moduledoc """
  A directed communication channel between two processing-element ports.

  Each link models a FIFO buffer with configurable latency and capacity.
  Data written to a link at tick T becomes readable at tick T + latency.

  ## Mental model

  Think of a link as a pipeline: values enter one end and exit the other
  after a fixed number of clock ticks.  The `buffer` field holds a
  `:queue` whose length never exceeds `capacity`.

  ## Determinism guarantee

  Links are purely functional data structures.  Every operation returns a
  new link struct; nothing is mutated.  Two links with identical fields
  always produce identical behaviour, which makes execution fully
  deterministic.
  """

  @type coord :: {non_neg_integer(), non_neg_integer()}
  @type port_name :: atom()
  @type endpoint :: {coord(), port_name()}

  @type t :: %__MODULE__{
          from: endpoint(),
          to: endpoint(),
          latency: pos_integer(),
          capacity: pos_integer(),
          buffer: :queue.queue()
        }

  @enforce_keys [:from, :to]
  defstruct [:from, :to, latency: 1, capacity: 1, buffer: :queue.new()]

  @doc """
  Creates a new link between two endpoints.

  ## Examples

      iex> link = ExSystolic.Link.new({{0,0}, :east}, {{1,0}, :west})
      iex> link.from
      {{0, 0}, :east}
      iex> link.to
      {{1, 0}, :west}
      iex> link.latency
      1

  """
  @spec new(endpoint(), endpoint(), keyword()) :: t()
  def new(from, to, opts \\ []) do
    latency = Keyword.get(opts, :latency, 1)
    capacity = Keyword.get(opts, :capacity, 1)

    %__MODULE__{
      from: from,
      to: to,
      latency: latency,
      capacity: capacity,
      buffer: :queue.new()
    }
  end

  @doc """
  Writes a value into the link buffer.

  Returns `{:ok, link}` when the buffer has room, or `{:error, :full}` when
  the buffer already contains `capacity` items.

  ## Examples

      iex> link = ExSystolic.Link.new({{0,0}, :east}, {{1,0}, :west})
      iex> {:ok, link2} = ExSystolic.Link.write(link, 42)
      iex> ExSystolic.Link.read(link2)
      {42, _}

  """
  @spec write(t(), term()) :: {:ok, t()} | {:error, :full}
  def write(%__MODULE__{buffer: buf, capacity: cap} = link, value) do
    if :queue.len(buf) >= cap do
      {:error, :full}
    else
      {:ok, %{link | buffer: :queue.in(value, buf)}}
    end
  end

  @doc """
  Reads and removes the oldest value from the link buffer (FIFO).

  Returns `{value, link}` when the buffer is non-empty, or `{:empty, link}`
  when nothing has been written yet.

  ## Examples

      iex> link = ExSystolic.Link.new({{0,0}, :east}, {{1,0}, :west})
      iex> {:ok, link2} = ExSystolic.Link.write(link, 99)
      iex> {val, _link3} = ExSystolic.Link.read(link2)
      iex> val
      99

  """
  @spec read(t()) :: {term(), t()} | {:empty, t()}
  def read(%__MODULE__{buffer: buf} = link) do
    case :queue.out(buf) do
      {{:value, val}, new_buf} ->
        {val, %{link | buffer: new_buf}}

      {:empty, _} ->
        {:empty, link}
    end
  end

  @doc """
  Peeks at the oldest value without removing it.

  ## Examples

      iex> link = ExSystolic.Link.new({{0,0}, :east}, {{1,0}, :west})
      iex> {:ok, link2} = ExSystolic.Link.write(link, 7)
      iex> ExSystolic.Link.peek(link2)
      {:ok, 7}

  """
  @spec peek(t()) :: {:ok, term()} | :empty
  def peek(%__MODULE__{buffer: buf}) do
    case :queue.peek(buf) do
      {:value, val} -> {:ok, val}
      :empty -> :empty
    end
  end

  @doc """
  Returns the number of items currently in the buffer.

  ## Examples

      iex> link = ExSystolic.Link.new({{0,0}, :east}, {{1,0}, :west}, capacity: 3)
      iex> ExSystolic.Link.size(link)
      0
      iex> {:ok, link2} = ExSystolic.Link.write(link, 1)
      iex> {:ok, link3} = ExSystolic.Link.write(link2, 2)
      iex> ExSystolic.Link.size(link3)
      2

  """
  @spec size(t()) :: non_neg_integer()
  def size(%__MODULE__{buffer: buf}), do: :queue.len(buf)

  @doc """
  Returns whether the link buffer is empty.

  ## Examples

      iex> link = ExSystolic.Link.new({{0,0}, :east}, {{1,0}, :west})
      iex> ExSystolic.Link.empty?(link)
      true

  """
  @spec empty?(t()) :: boolean()
  def empty?(%__MODULE__{buffer: buf}), do: :queue.is_empty(buf)

  @doc """
  Advances the link by one tick: drains the buffer if latency has expired.

  In the interpreted backend this is handled at the Array level; this
  function exists for unit-testing the link in isolation.  With latency=1
  (the default), a value written at tick T is readable at tick T+1, so
  `tick/1` is effectively a no-op on the buffer itself -- the Clock
  manages read-then-write ordering.

  ## Examples

      iex> link = ExSystolic.Link.new({{0,0}, :east}, {{1,0}, :west})
      iex> ExSystolic.Link.tick(link) == link
      true

  """
  @spec tick(t()) :: t()
  def tick(%__MODULE__{} = link), do: link
end
