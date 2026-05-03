defmodule ExSystolic.Backend.LinkOps do
  @moduledoc """
  Shared link-buffer operations used by all backends.

  Centralizes the three operations that every backend must perform
  every tick:

  1. **`inject_streams/2`** -- push items from external input streams
     into boundary link buffers, deferring values when a target link is
     full or absent.
  2. **`drain_links/2`** -- read every link buffer once, returning a
     map of `{coord, port} => value` (or `:empty`) and the drained
     link list.
  3. **`write_pe_outputs/2`** -- write PE-produced values into the
     link whose `from` endpoint matches; silently drop output for
     ports with no matching link or for full buffers.

  ## Why a shared module?

  Three near-identical implementations previously lived in `Clock`,
  `Backend.Interpreted`, and `Backend.Partitioned`, each with subtle
  differences.  Centralization eliminates the bug-in-three-places risk.

  ## Determinism

  All operations are pure functions over their inputs.  Iteration
  order is deterministic (Map iteration over the Erlang term order is
  stable for a given map shape).

  ## Performance

  The current implementation uses `Enum.find_index` + `List.replace_at`
  patterns, which are O(n) per write.  For a 4×4 array with 24 links
  this is acceptable; for larger arrays an indexed map representation
  should be considered.  See review item 2.1.
  """

  alias ExSystolic.Link

  @type stream_key :: {term(), atom()}
  @type input_streams :: %{stream_key() => [term()]}
  @type tick_outputs :: %{term() => %{atom() => term()}}
  @type inputs_map :: %{stream_key() => term() | :empty}

  @doc """
  Injects items from `input_streams` into the matching boundary link.

  For each `{coord, port}` key in `input_streams`:

  - If the corresponding link is found and accepts the write, the
    head of the stream is consumed.  When the stream is exhausted the
    key is removed; otherwise the tail is retained.
  - If the link is full, the entire stream (including the head) is
    deferred to the next tick.
  - If no matching link exists, the stream is silently dropped.

  Returns `{updated_links, remaining_streams}`.
  """
  @spec inject_streams([Link.t()], input_streams()) :: {[Link.t()], input_streams()}
  def inject_streams(links, input_streams) do
    Enum.reduce(input_streams, {links, %{}}, fn {key, stream}, {acc_links, acc_streams} ->
      inject_one(acc_links, acc_streams, key, stream)
    end)
  end

  defp inject_one(links, streams, {coord, port} = key, [val | rest]) do
    idx = Enum.find_index(links, fn l -> l.to == {coord, port} end)
    do_inject(links, streams, key, idx, val, rest)
  end

  defp inject_one(links, streams, _key, _stream), do: {links, streams}

  defp do_inject(links, streams, _key, nil, _val, _rest), do: {links, streams}

  defp do_inject(links, streams, key, idx, val, rest) do
    link = Enum.at(links, idx)

    case Link.write(link, val) do
      {:ok, new_link} ->
        new_links = List.replace_at(links, idx, new_link)
        new_streams = if rest == [], do: streams, else: Map.put(streams, key, rest)
        {new_links, new_streams}

      {:error, :full} ->
        {links, Map.put(streams, key, [val | rest])}
    end
  end

  @doc """
  Reads every link buffer once, returning the input map and drained
  links.

  Each `{coord, port}` in `input_ports` is looked up in the link list:

  - If a matching link exists, its head value is read (drained) and
    placed in the output map; the link is updated to remove the head.
  - If no matching link exists, the value is `:empty`.

  Returns `{inputs_map, drained_links}`.
  """
  @spec drain_links([Link.t()], [stream_key()]) :: {inputs_map(), [Link.t()]}
  def drain_links(links, input_ports) do
    link_to_idx =
      for {link, idx} <- Enum.with_index(links), into: %{}, do: {link.to, idx}

    Enum.reduce(input_ports, {%{}, links}, fn {_coord, _port} = key, {acc_inputs, acc_links} ->
      idx = Map.get(link_to_idx, key)
      drain_one(acc_inputs, acc_links, key, idx)
    end)
  end

  defp drain_one(acc_inputs, acc_links, key, nil) do
    {Map.put(acc_inputs, key, :empty), acc_links}
  end

  defp drain_one(acc_inputs, acc_links, key, idx) do
    link = Enum.at(acc_links, idx)
    {val, new_link} = Link.read(link)
    new_links = List.replace_at(acc_links, idx, new_link)
    {Map.put(acc_inputs, key, val), new_links}
  end

  @doc """
  Writes PE outputs into the link whose `from` endpoint matches.

  For each `{coord, output_port_map}` in `tick_outputs`, every
  `{port, value}` is written to the link with `from == {coord, port}`.

  Outputs with no matching link are silently dropped (typical for the
  `:result` port which has no outgoing link).  Writes that fail
  because the buffer is full are also silently dropped (back-pressure
  is not modelled in the current backend).

  Returns the updated link list.
  """
  @spec write_pe_outputs([Link.t()], tick_outputs()) :: [Link.t()]
  def write_pe_outputs(links, tick_outputs) do
    Enum.reduce(tick_outputs, links, &write_pe_output_set/2)
  end

  defp write_pe_output_set({coord, outputs}, acc_links) do
    Enum.reduce(outputs, acc_links, fn {port, value}, links ->
      write_to_link(links, {coord, port}, value)
    end)
  end

  defp write_to_link(links, from_key, value) do
    idx = Enum.find_index(links, &(&1.from == from_key))

    if idx do
      link = Enum.at(links, idx)

      case Link.write(link, value) do
        {:ok, new_link} -> List.replace_at(links, idx, new_link)
        {:error, :full} -> links
      end
    else
      links
    end
  end
end
