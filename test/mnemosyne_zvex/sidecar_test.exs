defmodule MnemosyneZvex.SidecarTest do
  use ExUnit.Case, async: true

  alias Mnemosyne.Graph.Edge
  alias MnemosyneZvex.Fixtures
  alias MnemosyneZvex.Sidecar

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    {:ok, side} = Sidecar.open(Path.join(tmp_dir, "sidecar.dets"))
    %{side: side}
  end

  describe "links" do
    test "put_link adds bidirectional edges", %{side: side} do
      :ok = Sidecar.put_link(side, "a", "b", :provenance)

      assert %{provenance: a_to_b} = Sidecar.get_links(side, "a")
      assert MapSet.member?(a_to_b, "b")
      assert %{provenance: b_to_a} = Sidecar.get_links(side, "b")
      assert MapSet.member?(b_to_a, "a")
    end

    test "get_links returns empty link map when absent", %{side: side} do
      assert Sidecar.get_links(side, "missing") == Edge.empty_links()
    end

    test "put_links_batch composes many links in one pass", %{side: side} do
      :ok = Sidecar.put_links_batch(side, [{"a", "b", :sibling}, {"a", "c", :sibling}])

      assert %{sibling: set} = Sidecar.get_links(side, "a")
      assert MapSet.equal?(set, MapSet.new(["b", "c"]))
    end
  end

  describe "metadata" do
    test "put_metadata_many + get_metadata_many round-trip", %{side: side} do
      meta = Fixtures.meta(access_count: 3)
      :ok = Sidecar.put_metadata_many(side, %{"x" => meta})

      assert %{"x" => ^meta} = Sidecar.get_metadata_many(side, ["x", "missing"])
    end

    test "delete_metadata removes specified ids", %{side: side} do
      :ok = Sidecar.put_metadata_many(side, %{"x" => Fixtures.meta()})
      :ok = Sidecar.delete_metadata(side, ["x"])

      assert Sidecar.get_metadata_many(side, ["x"]) == %{}
    end
  end

  describe "type index" do
    test "add_to_type_index + ids_of_type", %{side: side} do
      :ok = Sidecar.add_to_type_index(side, :semantic, "s1")
      :ok = Sidecar.add_to_type_index(side, :semantic, "s2")
      :ok = Sidecar.add_to_type_index(side, :tag, "t1")

      assert MapSet.equal?(Sidecar.ids_of_type(side, :semantic), MapSet.new(["s1", "s2"]))
      assert MapSet.equal?(Sidecar.ids_of_type(side, :tag), MapSet.new(["t1"]))
    end
  end

  describe "remove_ids" do
    test "deletes links, metadata, scrubs back-refs, and strips type indexes", %{side: side} do
      :ok = Sidecar.put_link(side, "a", "b", :sibling)
      :ok = Sidecar.put_link(side, "c", "b", :sibling)
      :ok = Sidecar.put_metadata_many(side, %{"b" => Fixtures.meta()})
      :ok = Sidecar.add_to_type_index(side, :semantic, "b")
      :ok = Sidecar.add_to_type_index(side, :semantic, "a")

      :ok = Sidecar.remove_ids(side, ["b"])

      assert Sidecar.get_links(side, "b") == Edge.empty_links()
      assert %{sibling: a_links} = Sidecar.get_links(side, "a")
      refute MapSet.member?(a_links, "b")
      assert Sidecar.get_metadata_many(side, ["b"]) == %{}
      assert MapSet.equal?(Sidecar.ids_of_type(side, :semantic), MapSet.new(["a"]))
    end

    test "is a no-op on an empty id list", %{side: side} do
      assert :ok = Sidecar.remove_ids(side, [])
    end
  end

  test "open/close persist data across reopen", %{tmp_dir: tmp_dir, side: side} do
    :ok = Sidecar.put_metadata_many(side, %{"persist" => Fixtures.meta(access_count: 7)})
    :ok = Sidecar.sync(side)
    :ok = Sidecar.close(side)

    {:ok, reopened} = Sidecar.open(Path.join(tmp_dir, "sidecar.dets"))

    assert %{"persist" => meta} = Sidecar.get_metadata_many(reopened, ["persist"])
    assert meta.access_count == 7

    :ok = Sidecar.close(reopened)
  end
end
