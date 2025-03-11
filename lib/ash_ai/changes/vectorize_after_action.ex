defmodule AshAi.Changes.VectorizeAfterAction do
  use Ash.Resource.Change

  def change(changeset, opts, context) do
    Ash.Changeset.after_transaction(changeset, fn
      _changeset, {:error, error} ->
        {:error, error}

      changeset, {:ok, result} ->
        if changeset.action.name == :ash_ai_update_embeddings do
          {:ok, result}
        else
          apikey = System.fetch_env!("OPEN_AI_API_KEY")
          openai = OpenaiEx.new(apikey)

          changes =
            opts[:vectors]
            # TODO: get all vectors in one request? or Task.async_stream
            |> Enum.reduce(%{}, fn
              {source, dest}, acc ->
                if Ash.Changeset.changing_attribute?(changeset, source) do
                  text = Map.get(result, source)

                  embedding_req =
                    OpenaiEx.Embeddings.new(%{
                      input: text,
                      model: "text-embedding-3-large"
                    })

                  embedding =
                    OpenaiEx.Embeddings.create!(openai, embedding_req)["data"]
                    |> Enum.at(0)
                    |> Map.get("embedding")

                  Map.put(acc, dest, embedding)
                else
                  acc
                end

              {:full_text, name, used_attrs, fun}, acc ->
                if is_nil(used_attrs) ||
                     Enum.any?(used_attrs, &Ash.Changeset.changing_attribute?(changeset, &1)) do
                  text = fun.(result)

                  embedding_req =
                    OpenaiEx.Embeddings.new(%{
                      input: text,
                      model: "text-embedding-3-large"
                    })

                  embedding =
                    OpenaiEx.Embeddings.create!(openai, embedding_req)["data"]
                    |> Enum.at(0)
                    |> Map.get("embedding")

                  Map.put(acc, name, embedding)
                else
                  acc
                end
            end)

          result
          |> Ash.Changeset.for_update(
            :ash_ai_update_embeddings,
            changes,
            Ash.Context.to_opts(context, actor: %AshAi{})
          )
          |> Ash.update()
        end
    end)
  end

  def atomic(changeset, opts, context) do
    {:ok, change(changeset, opts, context)}
  end
end
