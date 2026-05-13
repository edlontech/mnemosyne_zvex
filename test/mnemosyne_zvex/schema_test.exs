defmodule MnemosyneZvex.SchemaTest do
  use ExUnit.Case, async: true

  alias MnemosyneZvex.Schema
  alias Zvex.Collection.Schema, as: ZvexSchema

  test "node_types/0 lists all seven Mnemosyne node types" do
    assert [:episodic, :semantic, :procedural, :subgoal, :source, :intent, :tag] =
             Schema.node_types()
  end

  test "node_type_string/1 returns canonical string form" do
    for t <- Schema.node_types() do
      assert Schema.node_type_string(t) == Atom.to_string(t)
    end
  end

  test "build/1 raises without :dimension" do
    assert_raise KeyError, fn -> Schema.build([]) end
  end

  test "build/1 produces a valid Zvex schema with expected fields and hnsw cosine defaults" do
    schema = Schema.build(dimension: 8)
    assert :ok = ZvexSchema.validate(schema)

    fields = Map.new(schema.fields, &{&1.name, &1})

    assert %{primary_key: true, data_type: :string} = fields["id"]

    assert %{data_type: :vector_fp32, dimension: 8, index: %{type: :hnsw, metric: :cosine, m: 16}} =
             fields["embedding"]

    assert %{data_type: :string, index: %{type: :invert}} = fields["node_type"]
    assert %{data_type: :bool} = fields["has_embedding"]
    assert %{data_type: :string, nullable: true} = fields["tag_label"]
    assert %{data_type: :string} = fields["payload"]
    assert %{data_type: :int64} = fields["created_at_ms"]
  end

  test "build/1 honours overrides" do
    schema =
      Schema.build(
        dimension: 4,
        index: :flat,
        metric: :l2,
        index_opts: []
      )

    fields = Map.new(schema.fields, &{&1.name, &1})
    assert %{index: %{type: :flat, metric: :l2}} = fields["embedding"]
  end
end
