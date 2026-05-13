defmodule MnemosyneZvex.EncodingTest do
  use ExUnit.Case, async: true

  alias Mnemosyne.Graph.Edge
  alias Mnemosyne.Graph.Node, as: NodeProtocol
  alias MnemosyneZvex.Encoding
  alias MnemosyneZvex.Fixtures
  alias MnemosyneZvex.Schema
  alias Zvex.Document
  alias Zvex.Vector

  @dim 8

  describe "encode/2" do
    test "round-trips a semantic node end-to-end" do
      node = Fixtures.sem("s1", embedding: List.duplicate(0.5, @dim))
      doc = Encoding.encode(node, @dim)
      fields = doc_to_fields_map(doc)

      assert "s1" = doc.pk
      assert {:string, "semantic"} = fields["node_type"]
      assert {:bool, true} = fields["has_embedding"]
      assert {:null, nil} = fields["tag_label"]
      assert {:string, payload} = fields["payload"]

      assert %{embedding: nil, links: links, proposition: "fact-s1"} =
               payload |> Base.decode64!() |> :erlang.binary_to_term()

      assert links == Edge.empty_links()
    end

    test "zero-vector + has_embedding=false for embedding-less nodes" do
      node = Fixtures.tag("t1", label: "topic")
      doc = Encoding.encode(node, @dim)
      fields = doc_to_fields_map(doc)

      assert {:bool, false} = fields["has_embedding"]
      assert {:vector_fp32, bin} = fields["embedding"]
      assert Vector.from_binary(bin, :fp32) |> Vector.to_list() == List.duplicate(0.0, @dim)
      assert {:string, "topic"} = fields["tag_label"]
    end

    test "subgoal description and trajectory id appear in their columns" do
      sub = Fixtures.sub("sg1", description: "ship feature", embedding: nil)
      epi = Fixtures.epi("e1", trajectory_id: "traj-7")

      assert {:string, "ship feature"} =
               doc_to_fields_map(Encoding.encode(sub, @dim))["subgoal_desc"]

      assert {:string, "traj-7"} =
               doc_to_fields_map(Encoding.encode(epi, @dim))["trajectory_id"]
    end

    test "node_type column always matches Schema.node_type_string/1" do
      for {builder, type} <- [
            {&Fixtures.sem/1, :semantic},
            {&Fixtures.proc/1, :procedural},
            {&Fixtures.epi/1, :episodic},
            {&Fixtures.sub/1, :subgoal},
            {&Fixtures.src/1, :source},
            {&Fixtures.intent/1, :intent},
            {&Fixtures.tag/1, :tag}
          ] do
        node = builder.("x")
        fields = doc_to_fields_map(Encoding.encode(node, @dim))
        assert fields["node_type"] == {:string, Schema.node_type_string(type)}
      end
    end
  end

  describe "decode/1" do
    test "reconstructs a node identical to the original (minus links)" do
      original = Fixtures.sem("s1", embedding: List.duplicate(0.25, @dim))
      doc = Encoding.encode(original, @dim)
      decoded = Encoding.decode(doc_to_fields_map(doc))

      assert %{original | links: Edge.empty_links()} == decoded
      assert NodeProtocol.embedding(decoded) == List.duplicate(0.25, @dim)
    end

    test "reconstructs an embedding-less node with embedding: nil" do
      original = Fixtures.tag("t1", embedding: nil)
      doc = Encoding.encode(original, @dim)
      decoded = Encoding.decode(doc_to_fields_map(doc))

      assert NodeProtocol.embedding(decoded) == nil
    end
  end

  defp doc_to_fields_map(%Document{fields: fields}), do: fields
end
