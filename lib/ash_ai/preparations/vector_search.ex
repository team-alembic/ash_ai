defmodule AshAi.Preparations.VectorSearch do
  use Ash.Resource.Preparation
  require Ash.Sort

  @impl true
  def prepare(query, opts, _context) do
    Ash.Query.before_action(query, fn query ->
      apikey = System.fetch_env!("OPEN_AI_API_KEY")
      openai = OpenaiEx.new(apikey)

      embedding_req =
        OpenaiEx.Embeddings.new(%{
          input: query.arguments.query,
          model: "text-embedding-3-large"
        })

      query_vec =
        OpenaiEx.Embeddings.create!(openai, embedding_req)["data"]
        |> Enum.at(0)
        |> Map.get("embedding")

      sort_expr =
        query.arguments.targets
        |> Enum.map(&Keyword.get(opts[:available_targets], &1))
        |> Enum.filter(& &1)
        |> Enum.reduce(nil, fn target, expr ->
          if expr do
            expr(^expr + vector_cosine_distance(^ref(target), ^query_vec))
          else
            expr(vector_cosine_distance(^ref(target), ^query_vec))
          end
        end)

      Ash.Query.sort(query, {Ash.Sort.expr_sort(^sort_expr), :desc})
    end)
  end
end
