defmodule AshAi.Calculations.VectorSimilarity do
  use Ash.Resource.Calculation

  def expression(opts, context) do
    apikey = System.fetch_env!("OPEN_AI_API_KEY")
    openai = OpenaiEx.new(apikey)

    embedding_req =
      OpenaiEx.Embeddings.new(%{input: context.arguments.query, model: "text-embedding-3-large"})

    query_vec =
      OpenaiEx.Embeddings.create!(openai, embedding_req)["data"]
      |> Enum.at(0)
      |> Map.get("embedding")

    case context.arguments[:distance_algorithm] do
      :l2 ->
        expr(1 - vector_l2_distance(^ref(opts[:name]), ^query_vec))

      :cosine ->
        expr(1 - vector_cosine_distance(^ref(opts[:name]), ^query_vec))
    end
  end
end
