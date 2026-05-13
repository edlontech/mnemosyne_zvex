defmodule MnemosyneZvex.Recall do
  @moduledoc false

  alias Mnemosyne.Graph.Node, as: NodeProtocol
  alias Mnemosyne.ValueFunction
  alias MnemosyneZvex.Backend
  alias MnemosyneZvex.Encoding
  alias MnemosyneZvex.Errors
  alias MnemosyneZvex.Schema
  alias MnemosyneZvex.Sidecar
  alias MnemosyneZvex.Telemetry, as: T
  alias Zvex.Query
  alias Zvex.Vector

  @type scored_node :: {struct(), float()}

  @doc false
  @spec find_candidates(
          [atom()],
          [float()],
          [[float()]],
          %{module: module(), params: %{atom() => map()}},
          keyword(),
          Backend.t()
        ) :: {:ok, [scored_node()], Backend.t()} | {:error, Mnemosyne.Errors.error()}
  def find_candidates(
        node_types,
        query_embedding,
        tag_embeddings,
        vf_config,
        _opts,
        %Backend{} = state
      ) do
    vf_module = Map.get(vf_config, :module, ValueFunction.Default)
    vectors = [query_embedding | tag_embeddings]

    try do
      per_type =
        Enum.map(node_types, fn type ->
          score_type(state, type, vectors, vf_config, vf_module)
        end)

      deduped =
        per_type
        |> List.flatten()
        |> Enum.uniq_by(fn {node, _score} -> NodeProtocol.id(node) end)

      {:ok, deduped, state}
    catch
      {:zvex_error, err} -> {:error, Errors.translate(err, :find_candidates)}
    end
  end

  defp score_type(%Backend{} = state, type, vectors, vf_config, vf_module) do
    params = get_in(vf_config, [:params, type]) || %{}
    threshold = Map.get(params, :threshold, 0.0)
    top_k = Map.get(params, :top_k, 20)
    over_fetch = top_k * state.fetch_multiplier

    T.span(
      :find_candidates,
      %{type: type, vectors_searched: length(vectors)},
      fn ->
        raw_hits =
          Enum.flat_map(vectors, fn vec ->
            run_query!(state, type, vec, over_fetch)
          end)

        best_per_id = pick_best_per_id(raw_hits, state.metric)

        meta_map =
          Sidecar.get_metadata_many(
            state.sidecar,
            Enum.map(best_per_id, fn {pk, _node, _r} -> pk end)
          )

        scored =
          for {pk, node, relevance} <- best_per_id do
            meta = Map.get(meta_map, pk)
            {node, vf_module.score(relevance, node, meta, params)}
          end

        result =
          scored
          |> Enum.filter(fn {_n, s} -> s >= threshold end)
          |> Enum.sort_by(&elem(&1, 1), :desc)
          |> Enum.take(top_k)

        {result, %{raw_hits: length(raw_hits), kept: length(result)}}
      end
    )
  end

  defp run_query!(%Backend{collection: coll}, type, vec, over_fetch) do
    filter = "node_type = '#{Schema.node_type_string(type)}' AND has_embedding = true"

    query =
      Query.new()
      |> Query.field("embedding")
      |> Query.vector(Vector.from_list(vec, :fp32))
      |> Query.filter(filter)
      |> Query.top_k(over_fetch)
      |> Query.output_fields(["payload", "has_embedding"])
      |> Query.include_vector(true)

    case Query.execute(query, coll) do
      {:ok, results} -> results
      {:error, err} -> throw({:zvex_error, err})
    end
  end

  defp pick_best_per_id(raw_hits, metric) do
    selector =
      case metric do
        :ip -> &Enum.max_by(&1, fn h -> h.score end)
        _ -> &Enum.min_by(&1, fn h -> h.score end)
      end

    raw_hits
    |> Enum.group_by(& &1.pk)
    |> Enum.map(fn {pk, hits} ->
      best = selector.(hits)
      node = Encoding.decode(best.fields)
      {pk, node, score_to_relevance(best.score, metric)}
    end)
  end

  defp score_to_relevance(distance, :cosine), do: max(1.0 - distance, 0.0)
  defp score_to_relevance(distance, :l2), do: 1.0 / (1.0 + distance)
  defp score_to_relevance(score, :ip), do: max(score, 0.0)
end
