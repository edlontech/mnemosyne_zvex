defmodule MnemosyneZvex.Encoding do
  @moduledoc """
  Encodes `Mnemosyne.Graph.Node.*` structs into `Zvex.Document` values for
  Zvex storage, and decodes them back. The `:links` field is stripped on
  encode and re-attached by the caller (from the sidecar). The `:embedding`
  field is encoded into the dedicated vector column.
  """

  alias Mnemosyne.Graph.Edge
  alias Mnemosyne.Graph.Node, as: NodeProtocol
  alias Mnemosyne.Graph.Node.Episodic
  alias Mnemosyne.Graph.Node.Intent
  alias Mnemosyne.Graph.Node.Procedural
  alias Mnemosyne.Graph.Node.Semantic
  alias Mnemosyne.Graph.Node.Source
  alias Mnemosyne.Graph.Node.Subgoal
  alias Mnemosyne.Graph.Node.Tag
  alias MnemosyneZvex.Schema
  alias Zvex.Document
  alias Zvex.Vector

  @doc "Encodes a Mnemosyne node into a `Zvex.Document` ready for upsert."
  @spec encode(struct(), pos_integer()) :: Document.t()
  def encode(node, dimension) do
    type = NodeProtocol.node_type(node)
    embedding = NodeProtocol.embedding(node)
    {vector, has_embedding?} = embedding_to_vector(embedding, dimension)

    stripped =
      node
      |> Map.put(:links, Edge.empty_links())
      |> Map.put(:embedding, nil)

    # TODO: drop Base64 once Zvex probe-order respects schema type (deps/zvex/.../zig/document.zig probe_types).
    payload = stripped |> :erlang.term_to_binary([:compressed]) |> Base.encode64()
    created_at_ms = node.created_at |> DateTime.to_unix(:millisecond)

    id = NodeProtocol.id(node)

    Document.new()
    |> Document.put_pk(id)
    |> Document.put("id", id)
    |> Document.put("embedding", vector)
    |> Document.put("node_type", Schema.node_type_string(type))
    |> Document.put("has_embedding", has_embedding?)
    |> put_nullable_string("tag_label", tag_label(node))
    |> put_nullable_string("subgoal_desc", subgoal_desc(node))
    |> put_nullable_string("trajectory_id", trajectory_id(node))
    |> Document.put("payload", payload, :string)
    |> Document.put("created_at_ms", created_at_ms)
  end

  @doc "Encodes a list of nodes."
  @spec encode_many([struct()], pos_integer()) :: [Document.t()]
  def encode_many(nodes, dimension), do: Enum.map(nodes, &encode(&1, dimension))

  @doc """
  Decodes a Zvex document fields map back into the original Mnemosyne node
  struct. The returned struct has `:links` set to empty — the caller must
  merge in the sidecar links before returning to Mnemosyne.
  """
  @spec decode(map()) :: struct()
  def decode(%{"payload" => {:string, payload}} = fields) when is_binary(payload) do
    # TODO: drop Base64 once Zvex probe-order respects schema type (deps/zvex/.../zig/document.zig probe_types).
    base = payload |> Base.decode64!() |> :erlang.binary_to_term()

    case fields["has_embedding"] do
      {:bool, true} ->
        %{"embedding" => {_etype, embedding_binary}} = fields
        embedding = embedding_binary |> Vector.from_binary(:fp32) |> Vector.to_list()
        %{base | embedding: embedding}

      _ ->
        base
    end
  end

  @doc "Recognises the seven supported Mnemosyne node-struct modules."
  @spec node_module?(module()) :: boolean()
  def node_module?(mod),
    do: mod in [Episodic, Semantic, Procedural, Subgoal, Source, Intent, Tag]

  defp put_nullable_string(doc, field, nil), do: Document.put_null(doc, field)
  defp put_nullable_string(doc, field, value), do: Document.put(doc, field, value, :string)

  defp embedding_to_vector(nil, dimension),
    do: {Vector.from_list(List.duplicate(0.0, dimension), :fp32), false}

  defp embedding_to_vector(list, _dimension) when is_list(list),
    do: {Vector.from_list(list, :fp32), true}

  defp tag_label(%Tag{label: label}), do: label
  defp tag_label(_), do: nil

  defp subgoal_desc(%Subgoal{description: desc}), do: desc
  defp subgoal_desc(_), do: nil

  defp trajectory_id(%Episodic{trajectory_id: id}), do: id
  defp trajectory_id(_), do: nil
end
