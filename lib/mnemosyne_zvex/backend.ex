defmodule MnemosyneZvex.Backend do
  @moduledoc """
  Mnemosyne `GraphBackend` implementation backed by a per-repo Zvex collection
  and a DETS sidecar.

  ## Options

    * `:path` - required. Directory under which `zvex/` and `sidecar.dets`
      will live.
    * `:dimension` - required positive integer. Embedding dimension; must
      match the Mnemosyne `embedding` adapter.
    * `:index` - `:hnsw | :ivf | :flat`. Default `:hnsw`.
    * `:metric` - `:cosine | :l2 | :ip`. Default `:cosine`.
    * `:index_opts` - keyword list of index-specific options. Default
      `[m: 16, ef_construction: 200]`.
    * `:fetch_multiplier` - over-fetch factor for `find_candidates/6`. Default
      `3`. Larger values give the value function more candidates to rerank
      at the cost of NIF work.
  """

  @behaviour Mnemosyne.GraphBackend

  alias Mnemosyne.Graph.Node, as: NodeProtocol
  alias MnemosyneZvex.Encoding
  alias MnemosyneZvex.Errors
  alias MnemosyneZvex.Schema
  alias MnemosyneZvex.Sidecar
  alias MnemosyneZvex.Telemetry, as: T
  alias Zvex.Collection

  defstruct [
    :collection,
    :sidecar,
    :dimension,
    :index,
    :metric,
    :fetch_multiplier
  ]

  @type t :: %__MODULE__{
          collection: Collection.t(),
          sidecar: Sidecar.t(),
          dimension: pos_integer(),
          index: atom(),
          metric: atom(),
          fetch_multiplier: pos_integer()
        }

  @impl true
  def init(opts) do
    path = Keyword.fetch!(opts, :path)
    dimension = Keyword.fetch!(opts, :dimension)
    index = Keyword.get(opts, :index, :hnsw)
    metric = Keyword.get(opts, :metric, :cosine)
    fetch_multiplier = Keyword.get(opts, :fetch_multiplier, 3)

    zvex_path = Path.join(path, "zvex")
    sidecar_path = Path.join(path, "sidecar.dets")

    T.span(:init, %{path: path}, fn ->
      schema = Schema.build(opts)

      with {:ok, collection} <- open_or_create_collection(zvex_path, schema),
           {:ok, sidecar} <- Sidecar.open(sidecar_path) do
        state = %__MODULE__{
          collection: collection,
          sidecar: sidecar,
          dimension: dimension,
          index: index,
          metric: metric,
          fetch_multiplier: fetch_multiplier
        }

        {{:ok, state}, %{}}
      else
        {:error, reason} -> {{:error, Errors.translate(reason, :init)}, %{}}
      end
    end)
  end

  @doc "Closes both the Zvex collection and the DETS sidecar."
  @spec close(t()) :: :ok
  def close(%__MODULE__{collection: collection, sidecar: sidecar}) do
    _ = Collection.close(collection)
    _ = Sidecar.close(sidecar)
    :ok
  end

  @impl true
  def apply_changeset(%Mnemosyne.Graph.Changeset{} = cs, %__MODULE__{} = state) do
    T.span(
      :apply_changeset,
      %{nodes: length(cs.additions), links: length(cs.links), metadata: map_size(cs.metadata)},
      fn ->
        docs = Encoding.encode_many(cs.additions, state.dimension)

        with :ok <- upsert_docs(state.collection, docs),
             :ok <- index_additions(state.sidecar, cs.additions),
             :ok <- Sidecar.put_links_batch(state.sidecar, cs.links),
             :ok <- Sidecar.put_metadata_many(state.sidecar, cs.metadata),
             :ok <- Sidecar.sync(state.sidecar) do
          {{:ok, state}, %{}}
        else
          {:error, reason} -> {{:error, Errors.translate(reason, :apply_changeset)}, %{}}
        end
      end
    )
  end

  @impl true
  def delete_nodes(ids, %__MODULE__{} = state) when is_list(ids) do
    T.span(:delete_nodes, %{count: length(ids)}, fn ->
      with {:ok, %{errors: _, success: _}} <- Collection.delete(state.collection, ids),
           :ok <- Sidecar.remove_ids(state.sidecar, ids),
           :ok <- Sidecar.sync(state.sidecar) do
        {{:ok, state}, %{}}
      else
        {:error, reason} -> {{:error, Errors.translate(reason, :delete_nodes)}, %{}}
      end
    end)
  end

  @impl true
  def find_candidates(
        node_types,
        query_embedding,
        tag_embeddings,
        vf_config,
        opts,
        %__MODULE__{} = state
      ) do
    MnemosyneZvex.Recall.find_candidates(
      node_types,
      query_embedding,
      tag_embeddings,
      vf_config,
      opts,
      state
    )
  end

  @impl true
  def get_node(id, %__MODULE__{} = state) do
    T.span(:get_node, %{id: id}, fn ->
      case Collection.fetch(state.collection, [id]) do
        {:ok, []} ->
          {{:ok, nil, state}, %{hit: false}}

        {:ok, [doc]} ->
          node = decode_with_links(doc, state.sidecar)
          {{:ok, node, state}, %{hit: true}}

        {:error, err} ->
          {{:error, Errors.translate(err, :get_node)}, %{}}
      end
    end)
  end

  @impl true
  def get_linked_nodes(node_ids, _edge_type, %__MODULE__{} = state) do
    case Collection.fetch(state.collection, node_ids) do
      {:ok, docs} ->
        nodes =
          docs
          |> Enum.map(&decode_with_links(&1, state.sidecar))
          |> Enum.uniq_by(&NodeProtocol.id/1)

        {:ok, nodes, state}

      {:error, err} ->
        {:error, Errors.translate(err, :get_linked_nodes)}
    end
  end

  @impl true
  def get_metadata(node_ids, %__MODULE__{} = state) do
    {:ok, Sidecar.get_metadata_many(state.sidecar, node_ids), state}
  end

  @impl true
  def update_metadata(entries, %__MODULE__{} = state) do
    case Sidecar.put_metadata_many(state.sidecar, entries) do
      :ok -> {:ok, state}
      {:error, reason} -> {:error, Errors.translate(reason, :update_metadata)}
    end
  end

  @impl true
  def delete_metadata(node_ids, %__MODULE__{} = state) do
    case Sidecar.delete_metadata(state.sidecar, node_ids) do
      :ok -> {:ok, state}
      {:error, reason} -> {:error, Errors.translate(reason, :delete_metadata)}
    end
  end

  @impl true
  def get_nodes_by_type(node_types, %__MODULE__{} = state) do
    ids =
      node_types
      |> Enum.flat_map(&MapSet.to_list(Sidecar.ids_of_type(state.sidecar, &1)))
      |> Enum.uniq()

    case Collection.fetch(state.collection, ids) do
      {:ok, docs} ->
        nodes = Enum.map(docs, &decode_with_links(&1, state.sidecar))
        {:ok, nodes, state}

      {:error, err} ->
        {:error, Errors.translate(err, :get_nodes_by_type)}
    end
  end

  defp upsert_docs(_collection, []), do: :ok

  defp upsert_docs(collection, docs) do
    case Collection.upsert(collection, docs) do
      {:ok, %{errors: 0}} -> :ok
      {:ok, %{errors: n}} -> {:error, {:partial_upsert, n}}
      {:error, _} = err -> err
    end
  end

  defp index_additions(sidecar, additions) do
    Enum.reduce_while(additions, :ok, fn node, :ok ->
      type = NodeProtocol.node_type(node)
      id = NodeProtocol.id(node)

      case Sidecar.add_to_type_index(sidecar, type, id) do
        :ok -> {:cont, :ok}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  defp decode_with_links(%Zvex.Document{} = doc, sidecar) do
    base = Encoding.decode(doc_to_fields_map(doc))
    links = Sidecar.get_links(sidecar, NodeProtocol.id(base))
    %{base | links: links}
  end

  defp doc_to_fields_map(%Zvex.Document{fields: fields}), do: fields

  defp open_or_create_collection(zvex_path, schema) do
    if File.exists?(zvex_path) do
      Collection.open(zvex_path)
    else
      with :ok <- File.mkdir_p(Path.dirname(zvex_path)) do
        Collection.create(zvex_path, schema)
      end
    end
  end
end
