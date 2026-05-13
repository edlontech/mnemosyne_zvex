defmodule MnemosyneZvex.BackendTest do
  use MnemosyneZvex.BackendCase, async: true

  alias Mnemosyne.NodeMetadata
  alias MnemosyneZvex.Backend
  alias MnemosyneZvex.Sidecar

  describe "init/1 and close/1" do
    test "init creates a fresh collection and sidecar", %{state: state, tmp_dir: tmp_dir} do
      assert File.dir?(Path.join(tmp_dir, "zvex"))
      assert File.exists?(Path.join(tmp_dir, "sidecar.dets"))
      assert %Backend{dimension: 8, fetch_multiplier: 4} = state
    end

    test "init reopens an existing collection without error", %{tmp_dir: tmp_dir, state: state} do
      :ok = Backend.close(state)

      assert {:ok, reopened} = Backend.init(path: tmp_dir, dimension: 8, fetch_multiplier: 4)
      :ok = Backend.close(reopened)
    end
  end

  describe "get_node/2" do
    test "returns nil when the node is not present", %{state: state} do
      assert {:ok, nil, ^state} = Backend.get_node("missing", state)
    end
  end

  describe "metadata pass-through" do
    test "update_metadata + get_metadata round-trip", %{state: state} do
      meta = NodeMetadata.new(access_count: 5)
      assert {:ok, state} = Backend.update_metadata(%{"x" => meta}, state)
      assert {:ok, %{"x" => ^meta}, ^state} = Backend.get_metadata(["x", "y"], state)
    end

    test "delete_metadata removes the entry", %{state: state} do
      :ok = Sidecar.put_metadata_many(state.sidecar, %{"x" => NodeMetadata.new()})
      assert {:ok, state} = Backend.delete_metadata(["x"], state)
      assert {:ok, %{}, ^state} = Backend.get_metadata(["x"], state)
    end
  end

  describe "get_nodes_by_type/2 (Zvex-side filter query)" do
    test "returns [] when the collection is empty", %{state: state} do
      assert {:ok, [], ^state} = Backend.get_nodes_by_type([:semantic], state)
    end

    test "filters out other node types", %{state: state} do
      alias Mnemosyne.Graph.Changeset

      cs =
        Changeset.new()
        |> Changeset.add_node(sem("s1"))
        |> Changeset.add_node(sem("s2"))
        |> Changeset.add_node(proc("p1"))
        |> Changeset.add_node(tag("t1"))

      {:ok, state} = Backend.apply_changeset(cs, state)

      assert {:ok, semantics, _} = Backend.get_nodes_by_type([:semantic], state)
      assert Enum.map(semantics, & &1.id) |> Enum.sort() == ["s1", "s2"]

      assert {:ok, procs, _} = Backend.get_nodes_by_type([:procedural], state)
      assert Enum.map(procs, & &1.id) == ["p1"]
    end

    test "returns embedding-less nodes (tags) too", %{state: state} do
      alias Mnemosyne.Graph.Changeset

      cs =
        Changeset.new()
        |> Changeset.add_node(tag("t1"))
        |> Changeset.add_node(tag("t2"))

      {:ok, state} = Backend.apply_changeset(cs, state)

      assert {:ok, tags, _} = Backend.get_nodes_by_type([:tag], state)
      assert Enum.map(tags, & &1.id) |> Enum.sort() == ["t1", "t2"]
    end

    test "dedupes across requested types", %{state: state} do
      alias Mnemosyne.Graph.Changeset

      cs =
        Changeset.new()
        |> Changeset.add_node(sem("s1"))
        |> Changeset.add_node(proc("p1"))

      {:ok, state} = Backend.apply_changeset(cs, state)

      assert {:ok, all, _} = Backend.get_nodes_by_type([:semantic, :procedural], state)
      assert Enum.map(all, & &1.id) |> Enum.sort() == ["p1", "s1"]
    end
  end

  describe "get_linked_nodes/3" do
    test "returns [] for unknown ids", %{state: state} do
      assert {:ok, [], ^state} = Backend.get_linked_nodes(["missing"], nil, state)
    end
  end

  test "close/1 is idempotent under repeated calls", %{state: state} do
    assert :ok = Backend.close(state)
    assert :ok = Backend.close(state)
  end

  describe "apply_changeset/2 + read-back contract suite" do
    alias Mnemosyne.Graph.Changeset
    alias Mnemosyne.Graph.Node.Semantic
    alias Mnemosyne.Graph.Node.Source

    test "persists nodes, retrievable via get_node with merged links", %{state: state} do
      s1 = sem("s1", embedding: vec(8))
      src1 = src("e1")

      cs =
        Changeset.new()
        |> Changeset.add_node(s1)
        |> Changeset.add_node(src1)
        |> Changeset.add_link("s1", "e1", :provenance)
        |> Changeset.put_metadata("s1", meta(access_count: 0))

      assert {:ok, state} = Backend.apply_changeset(cs, state)

      assert {:ok, %Semantic{id: "s1", links: links, proposition: "fact-s1"}, _} =
               Backend.get_node("s1", state)

      assert MapSet.member?(links[:provenance], "e1")

      assert {:ok, %Source{id: "e1", links: src_links}, _} = Backend.get_node("e1", state)
      assert MapSet.member?(src_links[:provenance], "s1")
    end

    test "get_nodes_by_type returns persisted nodes", %{state: state} do
      cs =
        Changeset.new()
        |> Changeset.add_node(sem("s1"))
        |> Changeset.add_node(sem("s2"))
        |> Changeset.add_node(proc("p1"))

      assert {:ok, state} = Backend.apply_changeset(cs, state)
      assert {:ok, semantics, _} = Backend.get_nodes_by_type([:semantic], state)
      assert Enum.map(semantics, & &1.id) |> Enum.sort() == ["s1", "s2"]
    end

    test "is idempotent under re-apply of the same changeset", %{state: state} do
      cs = Changeset.new() |> Changeset.add_node(sem("s1"))

      {:ok, state} = Backend.apply_changeset(cs, state)
      assert {:ok, _state} = Backend.apply_changeset(cs, state)
    end
  end

  describe "delete_nodes/2" do
    alias Mnemosyne.Graph.Changeset

    test "removes nodes, metadata, links, and back-references", %{state: state} do
      cs =
        Changeset.new()
        |> Changeset.add_node(sem("s1"))
        |> Changeset.add_node(src("e1"))
        |> Changeset.add_link("s1", "e1", :provenance)
        |> Changeset.put_metadata("s1", meta())

      {:ok, state} = Backend.apply_changeset(cs, state)
      {:ok, state} = Backend.delete_nodes(["s1"], state)

      assert {:ok, nil, _} = Backend.get_node("s1", state)
      assert {:ok, %{links: links}, _} = Backend.get_node("e1", state)
      refute MapSet.member?(links[:provenance], "s1")
      assert {:ok, %{}, _} = Backend.get_metadata(["s1"], state)
    end

    test "deleting an unknown id is a no-op", %{state: state} do
      assert {:ok, _state} = Backend.delete_nodes(["never-existed"], state)
    end
  end
end
