defmodule MnemosyneZvex.RecallTest do
  use MnemosyneZvex.BackendCase, async: true

  alias Mnemosyne.Graph.Changeset
  alias Mnemosyne.ValueFunction.Default, as: DefaultVF
  alias MnemosyneZvex.Backend

  @query_vec List.duplicate(1.0, 8)

  defp vf_config(params) do
    %{module: DefaultVF, params: params}
  end

  describe "find_candidates/6" do
    test "returns matching semantic node with highest score first", %{state: state} do
      relevant = sem("s1", embedding: List.duplicate(1.0, 8))
      orthogonal = sem("s2", embedding: List.duplicate(-1.0, 8))

      cs =
        Changeset.new()
        |> Changeset.add_node(relevant)
        |> Changeset.add_node(orthogonal)
        |> Changeset.put_metadata("s1", meta())
        |> Changeset.put_metadata("s2", meta())

      {:ok, state} = Backend.apply_changeset(cs, state)

      assert {:ok, results, _} =
               Backend.find_candidates(
                 [:semantic],
                 @query_vec,
                 [],
                 vf_config(%{semantic: %{top_k: 5}}),
                 [],
                 state
               )

      assert [{first, _} | _] = results
      assert first.id == "s1"
    end

    test "honours per-type top_k", %{state: state} do
      cs =
        Enum.reduce(1..6, Changeset.new(), fn i, acc ->
          id = "s#{i}"

          acc
          |> Changeset.add_node(sem(id, embedding: List.duplicate(1.0, 8)))
          |> Changeset.put_metadata(id, meta())
        end)

      {:ok, state} = Backend.apply_changeset(cs, state)

      assert {:ok, results, _} =
               Backend.find_candidates(
                 [:semantic],
                 @query_vec,
                 [],
                 vf_config(%{semantic: %{top_k: 2}}),
                 [],
                 state
               )

      assert length(results) == 2
    end

    test "drops candidates below the threshold", %{state: state} do
      good = sem("good", embedding: List.duplicate(1.0, 8))
      bad = sem("bad", embedding: List.duplicate(-1.0, 8))

      cs =
        Changeset.new()
        |> Changeset.add_node(good)
        |> Changeset.add_node(bad)
        |> Changeset.put_metadata("good", meta())
        |> Changeset.put_metadata("bad", meta())

      {:ok, state} = Backend.apply_changeset(cs, state)

      assert {:ok, results, _} =
               Backend.find_candidates(
                 [:semantic],
                 @query_vec,
                 [],
                 vf_config(%{semantic: %{top_k: 10, threshold: 0.2}}),
                 [],
                 state
               )

      assert Enum.map(results, fn {n, _} -> n.id end) == ["good"]
    end

    test "tag_embeddings widen the candidate pool via per-vector queries", %{state: state} do
      query_aligned = sem("qa", embedding: List.duplicate(1.0, 8))
      tag_aligned = sem("ta", embedding: List.duplicate(-1.0, 8))

      cs =
        Changeset.new()
        |> Changeset.add_node(query_aligned)
        |> Changeset.add_node(tag_aligned)
        |> Changeset.put_metadata("qa", meta())
        |> Changeset.put_metadata("ta", meta())

      {:ok, state} = Backend.apply_changeset(cs, state)

      assert {:ok, results, _} =
               Backend.find_candidates(
                 [:semantic],
                 @query_vec,
                 [List.duplicate(-1.0, 8)],
                 vf_config(%{semantic: %{top_k: 5}}),
                 [],
                 state
               )

      ids = results |> Enum.map(fn {n, _} -> n.id end) |> Enum.sort()
      assert ids == ["qa", "ta"]
    end

    test "dedupes a node that matches under multiple node_types", %{state: state} do
      shared = sem("dup", embedding: List.duplicate(1.0, 8))

      cs =
        Changeset.new()
        |> Changeset.add_node(shared)
        |> Changeset.put_metadata("dup", meta())

      {:ok, state} = Backend.apply_changeset(cs, state)

      assert {:ok, results, _} =
               Backend.find_candidates(
                 [:semantic, :semantic],
                 @query_vec,
                 [],
                 vf_config(%{semantic: %{top_k: 5}}),
                 [],
                 state
               )

      assert length(results) == 1
    end

    test "skips embedding-less nodes via has_embedding filter", %{state: state} do
      cs =
        Changeset.new()
        |> Changeset.add_node(tag("t1", embedding: nil))
        |> Changeset.put_metadata("t1", meta())

      {:ok, state} = Backend.apply_changeset(cs, state)

      assert {:ok, [], _} =
               Backend.find_candidates(
                 [:tag],
                 @query_vec,
                 [],
                 vf_config(%{tag: %{top_k: 5}}),
                 [],
                 state
               )
    end
  end
end
