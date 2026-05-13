defmodule MnemosyneZvex.IntegrationTest do
  use ExUnit.Case, async: false
  use AssertEventually, timeout: 2_000, interval: 50

  @moduletag :integration
  @moduletag :tmp_dir

  alias Mnemosyne.Graph.Changeset
  alias Mnemosyne.NodeMetadata
  alias MnemosyneZvex.Fixtures

  defmodule StubLLM do
    @moduledoc false
    @behaviour Mnemosyne.LLM

    @impl true
    def chat(_messages, _opts),
      do: {:ok, %Mnemosyne.LLM.Response{content: "", model: "stub"}}

    @impl true
    def chat_structured(_messages, _schema, _opts),
      do: {:ok, %Mnemosyne.LLM.Response{content: %{}, model: "stub"}}
  end

  defmodule StubEmbedding do
    @moduledoc false
    @behaviour Mnemosyne.Embedding

    @impl true
    def embed(_text, _opts) do
      {:ok, %Mnemosyne.Embedding.Response{vectors: [List.duplicate(0.0, 8)], model: "stub"}}
    end

    @impl true
    def embed_batch(texts, _opts) do
      vectors = Enum.map(texts, fn _ -> List.duplicate(0.0, 8) end)
      {:ok, %Mnemosyne.Embedding.Response{vectors: vectors, model: "stub"}}
    end
  end

  setup_all do
    config = %Mnemosyne.Config{
      llm: %{model: "stub", opts: %{}},
      embedding: %{model: "stub", opts: %{}}
    }

    {:ok, sup} =
      Mnemosyne.Supervisor.start_link(
        config: config,
        llm: StubLLM,
        embedding: StubEmbedding
      )

    on_exit(fn ->
      ref = Process.monitor(sup)
      Process.exit(sup, :shutdown)

      receive do
        {:DOWN, ^ref, :process, ^sup, _} -> :ok
      after
        5_000 -> :ok
      end
    end)

    :ok
  end

  setup %{tmp_dir: tmp_dir} do
    repo_id = "test-repo-#{:rand.uniform(1_000_000_000)}"

    {:ok, _pid} =
      Mnemosyne.open_repo(repo_id,
        backend: {MnemosyneZvex.Backend, path: tmp_dir, dimension: 8}
      )

    on_exit(fn -> _ = Mnemosyne.close_repo(repo_id) end)
    %{repo_id: repo_id}
  end

  test "Mnemosyne.open_repo + apply_changeset + get_node round-trip", %{repo_id: repo_id} do
    s1 = Fixtures.sem("s1", embedding: List.duplicate(1.0, 8))

    cs =
      Changeset.new()
      |> Changeset.add_node(s1)
      |> Changeset.put_metadata("s1", NodeMetadata.new())

    :ok = Mnemosyne.apply_changeset(repo_id, cs)

    assert_eventually(
      {:ok, %{id: "s1", proposition: "fact-s1"}} = Mnemosyne.get_node(repo_id, "s1")
    )
  end

  test "delete_nodes propagates", %{repo_id: repo_id} do
    cs =
      Changeset.new()
      |> Changeset.add_node(Fixtures.sem("kill-me"))
      |> Changeset.put_metadata("kill-me", NodeMetadata.new())

    :ok = Mnemosyne.apply_changeset(repo_id, cs)
    assert_eventually({:ok, %{id: "kill-me"}} = Mnemosyne.get_node(repo_id, "kill-me"))

    :ok = Mnemosyne.delete_nodes(repo_id, ["kill-me"])
    assert_eventually({:ok, nil} = Mnemosyne.get_node(repo_id, "kill-me"))
  end
end
