defmodule AshAi.Preparations.VectorSearch do
  use Ash.Resource.Preparation
  require Ash.Sort

  @impl true
  def prepare(query, opts, _context) do
    Ash.Query.before_action(query, fn query ->
      {embedding_model, embedding_opts} = AshAi.Info.vectorize_embedding_model!(query.resource)

      case embedding_model.generate([query.arguments.query], embedding_opts) do
        {:ok, [query_vec]} ->
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
      end
    end)
  end
end
