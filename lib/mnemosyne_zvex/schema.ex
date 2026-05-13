defmodule MnemosyneZvex.Schema do
  @moduledoc """
  Builds the per-repo `Zvex.Collection.Schema` used by `MnemosyneZvex.Backend`
  and centralises atom->string conversion for the `node_type` column.
  """

  alias Zvex.Collection.Schema

  @version 1

  @node_types [:episodic, :semantic, :procedural, :subgoal, :source, :intent, :tag]

  @doc "Schema layout version. Bumped if breaking column changes are introduced."
  @spec version() :: pos_integer()
  def version, do: @version

  @doc "Returns the canonical list of node-type atoms supported by the backend."
  @spec node_types() :: [atom()]
  def node_types, do: @node_types

  @doc """
  Stringifies a node-type atom for the `node_type` zvex column. Used by both
  the encoder (writes) and the filter builder (reads) so the two sites cannot
  diverge.
  """
  @spec node_type_string(atom()) :: String.t()
  def node_type_string(type) when type in @node_types, do: Atom.to_string(type)

  @doc """
  Builds a Zvex collection schema from backend opts.

  Required: `:dimension`. Optional: `:index` (default `:hnsw`), `:metric`
  (default `:cosine`), `:index_opts` (default `[m: 16, ef_construction: 200]`).
  """
  @spec build(keyword()) :: Schema.t()
  def build(opts) do
    dimension = Keyword.fetch!(opts, :dimension)
    index_type = Keyword.get(opts, :index, :hnsw)
    metric = Keyword.get(opts, :metric, :cosine)
    index_opts = Keyword.get(opts, :index_opts, m: 16, ef_construction: 200)

    embedding_index = [type: index_type, metric: metric] ++ index_opts

    Schema.new("mnemosyne_zvex_nodes")
    |> Schema.add_field("id", :string, primary_key: true)
    |> Schema.add_field("embedding", :vector_fp32,
      dimension: dimension,
      index: embedding_index
    )
    |> Schema.add_field("node_type", :string, index: [type: :invert])
    |> Schema.add_field("has_embedding", :bool)
    |> Schema.add_field("tag_label", :string, nullable: true, index: [type: :invert])
    |> Schema.add_field("subgoal_desc", :string, nullable: true, index: [type: :invert])
    |> Schema.add_field("trajectory_id", :string, nullable: true, index: [type: :invert])
    |> Schema.add_field("payload", :string)
    |> Schema.add_field("created_at_ms", :int64, index: [type: :invert])
  end
end
