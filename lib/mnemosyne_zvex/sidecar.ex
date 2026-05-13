defmodule MnemosyneZvex.Sidecar do
  @moduledoc """
  DETS-backed store for mutable per-node metadata and typed links between
  nodes. Lookups by `node_type` go straight to Zvex via a filtered query —
  no type-index is maintained here.

  Records:

      {{:links, node_id}, %{edge_type => MapSet.t(node_id)}}
      {{:meta,  node_id}, %Mnemosyne.NodeMetadata{}}
  """

  alias Mnemosyne.Graph.Edge

  defstruct [:ref, :path]

  @type t :: %__MODULE__{ref: :dets.tab_name(), path: charlist()}

  @doc "Opens a DETS table at the given path, creating it if needed."
  @spec open(Path.t()) :: {:ok, t()} | {:error, {:dets_error, term()}}
  def open(path) do
    charlist_path = String.to_charlist(path)

    with :ok <- File.mkdir_p(Path.dirname(path)),
         {:ok, ref} <- :dets.open_file(charlist_path, type: :set, auto_save: 60_000) do
      {:ok, %__MODULE__{ref: ref, path: charlist_path}}
    else
      {:error, reason} -> {:error, {:dets_error, reason}}
    end
  end

  @doc "Closes the underlying DETS table."
  @spec close(t()) :: :ok | {:error, {:dets_error, term()}}
  def close(%__MODULE__{ref: ref}) do
    case :dets.close(ref) do
      :ok -> :ok
      {:error, reason} -> {:error, {:dets_error, reason}}
    end
  end

  @doc "Flushes pending writes to disk."
  @spec sync(t()) :: :ok | {:error, {:dets_error, term()}}
  def sync(%__MODULE__{ref: ref}) do
    case :dets.sync(ref) do
      :ok -> :ok
      {:error, reason} -> {:error, {:dets_error, reason}}
    end
  end

  @doc "Adds a bidirectional link between two nodes."
  @spec put_link(t(), String.t(), String.t(), Edge.edge_type()) ::
          :ok | {:error, {:dets_error, term()}}
  def put_link(%__MODULE__{} = side, id_a, id_b, type) do
    with :ok <- merge_link(side, id_a, id_b, type) do
      merge_link(side, id_b, id_a, type)
    end
  end

  @doc "Adds many bidirectional links in one pass (no sync)."
  @spec put_links_batch(t(), [{String.t(), String.t(), Edge.edge_type()}]) ::
          :ok | {:error, {:dets_error, term()}}
  def put_links_batch(%__MODULE__{} = side, links) do
    Enum.reduce_while(links, :ok, fn {a, b, t}, :ok ->
      case put_link(side, a, b, t) do
        :ok -> {:cont, :ok}
        {:error, _} = e -> {:halt, e}
      end
    end)
  end

  @doc "Fetches the link map for a node id, defaulting to empty when absent."
  @spec get_links(t(), String.t()) :: %{Edge.edge_type() => MapSet.t()}
  def get_links(%__MODULE__{ref: ref}, id) do
    case :dets.lookup(ref, {:links, id}) do
      [{_, map}] -> map
      [] -> Edge.empty_links()
    end
  end

  @doc "Upserts a batch of metadata entries."
  @spec put_metadata_many(t(), %{String.t() => struct()}) ::
          :ok | {:error, {:dets_error, term()}}
  def put_metadata_many(%__MODULE__{ref: ref}, entries) do
    Enum.reduce_while(entries, :ok, fn {id, meta}, :ok ->
      case :dets.insert(ref, {{:meta, id}, meta}) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {:dets_error, reason}}}
      end
    end)
  end

  @doc "Looks up metadata for many node ids; missing ids are absent from the map."
  @spec get_metadata_many(t(), [String.t()]) :: %{String.t() => struct()}
  def get_metadata_many(%__MODULE__{ref: ref}, ids) do
    Enum.reduce(ids, %{}, fn id, acc ->
      case :dets.lookup(ref, {:meta, id}) do
        [{_, meta}] -> Map.put(acc, id, meta)
        [] -> acc
      end
    end)
  end

  @doc "Deletes metadata for the given ids."
  @spec delete_metadata(t(), [String.t()]) :: :ok | {:error, {:dets_error, term()}}
  def delete_metadata(%__MODULE__{ref: ref}, ids) do
    Enum.reduce_while(ids, :ok, fn id, :ok ->
      case :dets.delete(ref, {:meta, id}) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {:dets_error, reason}}}
      end
    end)
  end

  @doc """
  Removes the given ids from all sidecar tables and scrubs back-references
  from every surviving node's link set. Mirrors
  `Mnemosyne.GraphBackends.Persistence.DETS.strip_dead_refs/2`.
  """
  @spec remove_ids(t(), [String.t()]) :: :ok | {:error, {:dets_error, term()}}
  def remove_ids(%__MODULE__{ref: ref}, ids) do
    dead = MapSet.new(ids)

    with :ok <- strip_back_refs(ref, dead),
         :ok <- delete_link_rows(ref, ids) do
      delete_meta_rows(ref, ids)
    end
  end

  defp merge_link(%__MODULE__{ref: ref}, owner, other, type) do
    current =
      case :dets.lookup(ref, {:links, owner}) do
        [{_, map}] -> map
        [] -> Edge.empty_links()
      end

    updated = Map.update(current, type, MapSet.new([other]), &MapSet.put(&1, other))

    case :dets.insert(ref, {{:links, owner}, updated}) do
      :ok -> :ok
      {:error, reason} -> {:error, {:dets_error, reason}}
    end
  end

  defp strip_back_refs(ref, dead) do
    updates = :dets.foldl(&collect_back_ref_update(&1, &2, dead), [], ref)

    Enum.reduce_while(updates, :ok, fn {id, stripped}, :ok ->
      case :dets.insert(ref, {{:links, id}, stripped}) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {:dets_error, reason}}}
      end
    end)
  end

  defp collect_back_ref_update({{:links, id}, map}, acc, dead) do
    if MapSet.member?(dead, id), do: acc, else: maybe_strip_links(id, map, dead, acc)
  end

  defp collect_back_ref_update(_other, acc, _dead), do: acc

  defp maybe_strip_links(id, map, dead, acc) do
    stripped = Map.new(map, fn {t, ids} -> {t, MapSet.difference(ids, dead)} end)
    if stripped == map, do: acc, else: [{id, stripped} | acc]
  end

  defp delete_link_rows(ref, ids) do
    Enum.reduce_while(ids, :ok, fn id, :ok ->
      case :dets.delete(ref, {:links, id}) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {:dets_error, reason}}}
      end
    end)
  end

  defp delete_meta_rows(ref, ids) do
    Enum.reduce_while(ids, :ok, fn id, :ok ->
      case :dets.delete(ref, {:meta, id}) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {:dets_error, reason}}}
      end
    end)
  end
end
