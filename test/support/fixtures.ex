defmodule MnemosyneZvex.Fixtures do
  @moduledoc false

  alias Mnemosyne.Graph.Node.Episodic
  alias Mnemosyne.Graph.Node.Intent
  alias Mnemosyne.Graph.Node.Procedural
  alias Mnemosyne.Graph.Node.Semantic
  alias Mnemosyne.Graph.Node.Source
  alias Mnemosyne.Graph.Node.Subgoal
  alias Mnemosyne.Graph.Node.Tag
  alias Mnemosyne.NodeMetadata

  @dim 8

  def vec(n \\ @dim), do: Enum.map(1..n, fn _ -> :rand.uniform() end)

  def sem(id, opts \\ []) do
    %Semantic{
      id: id,
      proposition: Keyword.get(opts, :proposition, "fact-#{id}"),
      confidence: Keyword.get(opts, :confidence, 0.9),
      embedding: Keyword.get(opts, :embedding, vec(@dim)),
      created_at: Keyword.get(opts, :created_at, DateTime.utc_now())
    }
  end

  def proc(id, opts \\ []) do
    %Procedural{
      id: id,
      instruction: Keyword.get(opts, :instruction, "do thing #{id}"),
      condition: Keyword.get(opts, :condition, "when needed"),
      expected_outcome: Keyword.get(opts, :expected_outcome, "thing done"),
      return_score: Keyword.get(opts, :return_score),
      embedding: Keyword.get(opts, :embedding, vec(@dim))
    }
  end

  def epi(id, opts \\ []) do
    %Episodic{
      id: id,
      observation: Keyword.get(opts, :observation, "obs"),
      action: Keyword.get(opts, :action, "act"),
      state: Keyword.get(opts, :state, "state"),
      subgoal: Keyword.get(opts, :subgoal, "subgoal"),
      reward: Keyword.get(opts, :reward, 0.0),
      trajectory_id: Keyword.get(opts, :trajectory_id, "t-1"),
      embedding: Keyword.get(opts, :embedding, vec(@dim))
    }
  end

  def sub(id, opts \\ []) do
    %Subgoal{
      id: id,
      description: Keyword.get(opts, :description, "do X"),
      parent_goal: Keyword.get(opts, :parent_goal),
      embedding: Keyword.get(opts, :embedding)
    }
  end

  def src(id, opts \\ []) do
    %Source{
      id: id,
      episode_id: Keyword.get(opts, :episode_id, "e-1"),
      step_index: Keyword.get(opts, :step_index, 0),
      plain_text: Keyword.get(opts, :plain_text, "raw"),
      embedding: Keyword.get(opts, :embedding)
    }
  end

  def intent(id, opts \\ []) do
    %Intent{
      id: id,
      description: Keyword.get(opts, :description, "achieve X"),
      embedding: Keyword.get(opts, :embedding, vec(@dim))
    }
  end

  def tag(id, opts \\ []) do
    %Tag{
      id: id,
      label: Keyword.get(opts, :label, "topic-#{id}"),
      embedding: Keyword.get(opts, :embedding)
    }
  end

  def meta(opts \\ []) do
    NodeMetadata.new(
      created_at: Keyword.get(opts, :created_at, DateTime.utc_now()),
      access_count: Keyword.get(opts, :access_count, 0)
    )
  end
end
