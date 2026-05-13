# MnemosyneZvex

A [Mnemosyne](https://github.com/edlontech/mnemosyne) `GraphBackend` backed by
[Zvex](https://github.com/edlontech/zvex), an in-process vector database, plus
a DETS sidecar for typed links and mutable per-node metadata.

## Installation

```elixir
def deps do
  [
    {:mnemosyne_zvex, "~> 0.1.0"} # x-release-please-version
  ]
end
```

## Usage

```elixir
# Configure Mnemosyne's shared adapters once in your supervisor
children = [
  {Mnemosyne.Supervisor,
    config: %Mnemosyne.Config{
      llm: %{model: "gpt-4o", opts: %{}},
      embedding: %{model: "text-embedding-3-small", opts: %{}}
    },
    llm: MyApp.LLMAdapter,
    embedding: MyApp.EmbeddingAdapter}
]

# Then open a repo backed by MnemosyneZvex
{:ok, _pid} =
  Mnemosyne.open_repo("my-project",
    backend: {MnemosyneZvex.Backend,
      path: "/var/data/mnemosyne/my-project",
      dimension: 1536}
  )

# Use Mnemosyne normally
{:ok, session} = Mnemosyne.start_session("Help user plan a trip", repo: "my-project")
:ok = Mnemosyne.append(session, "User says they want to visit Tokyo", "Asking dates")
:ok = Mnemosyne.close_and_commit(session)

{:ok, memories} = Mnemosyne.recall("my-project", "What does the user want?")
```

## Options

| Option | Required | Default | Description |
|---|---|---|---|
| `:path` | yes | — | Directory under which `zvex/` and `sidecar.dets` will live |
| `:dimension` | yes | — | Embedding dimension (must match your `embedding` adapter) |
| `:index` | no | `:hnsw` | Vector index type: `:hnsw`, `:ivf`, or `:flat` |
| `:metric` | no | `:cosine` | Distance metric: `:cosine`, `:l2`, or `:ip` |
| `:index_opts` | no | `[m: 16, ef_construction: 200]` | Index-specific parameters |
| `:fetch_multiplier` | no | `3` | Over-fetch factor for value function reranking |
