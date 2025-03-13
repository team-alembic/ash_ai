defmodule AshAi.Transformers.Vectorize do
  use Spark.Dsl.Transformer

  import Spark.Dsl.Builder
  import Ash.Resource.Builder

  def after?(_), do: true

  def transform(dsl) do
    attrs =
      dsl
      |> AshAi.Info.vectorize_attributes!()

    uses_full_text = match?({:ok, _}, AshAi.Info.vectorize_full_text_text(dsl))

    if Enum.empty?(attrs) && !uses_full_text do
      {:ok, dsl}
    else
      if Ash.Resource.Info.data_layer(dsl) != AshPostgres.DataLayer do
        raise "AshAi vectorization only currently supports AshPostgres"
      end

      if Ash.Resource.Info.field(dsl, :full_text) do
        raise "AshAi vectorization currently does not work if there is a field called full_text"
      end

      attrs
      |> Enum.reduce({:ok, dsl}, &vectorize_attribute(&2, &1))
      |> full_text_vector()
      |> update_vectors_action()
      |> add_vector_search_action()
    end
  end

  defbuilder add_vector_search_action(dsl_state) do
    attrs =
      dsl_state
      |> AshAi.Info.vectorize_attributes!()

    {attrs, default} =
      case AshAi.Info.vectorize_full_text_text(dsl_state) do
        {:ok, _text} ->
          default = [full_text: AshAi.Info.vectorize_full_text_name!(dsl_state)]
          {attrs ++ default, [:full_text]}

        _ ->
          {attrs, Keyword.keys(attrs)}
      end

    case attrs do
      [] -> {:ok, dsl_state}
      attrs -> do_add_vector_search_action(dsl_state, attrs, default)
    end
  end

  defbuilder do_add_vector_search_action(dsl_state, attrs, default) do
    Ash.Resource.Builder.add_new_action(dsl_state, :read, :vector_search,
      arguments: [
        build_action_argument(:query, :string, allow_nil?: false),
        build_action_argument(:targets, {:array, :atom},
          constraints: [items: [one_of: Keyword.keys(attrs)]],
          default: default
        )
      ],
      preparations: [
        build_preparation({AshAi.Preparations.VectorSearch, available_targets: attrs})
      ]
    )
  end

  defbuilder update_vectors_action(dsl_state) do
    name = AshAi.Info.vectorize_full_text_name!(dsl_state)

    attrs =
      AshAi.Info.vectorize_attributes!(dsl_state)

    case AshAi.Info.vectorize_full_text_text(dsl_state) do
      {:ok, fun} ->
        used_attrs =
          case AshAi.Info.vectorize_full_text_used_attributes(dsl_state) do
            {:ok, attrs} -> attrs
            _ -> nil
          end

        attrs ++
          [{:full_text, name, used_attrs, fun}]

      _ ->
        attrs
    end
    |> case do
      [] ->
        {:ok, dsl_state}

      vectors ->
        dsl_state
        |> add_change({AshAi.Changes.VectorizeAfterAction, [vectors: vectors]})
        |> add_new_action(:update, :ash_ai_update_embeddings,
          accept: Enum.map(vectors, &elem(&1, 1)),
          require_atomic?: false
        )
    end
  end

  defbuilder vectorize_attribute(dsl_state, {_source, dest}) do
    embedding_model = AshAi.Info.vectorize_embedding_model!(dsl_state)

    dsl_state
    |> add_new_attribute(dest, :vector,
      constraints: [dimensions: embedding_model.dimensions()],
      select_by_default?: false
    )
  end

  defbuilder full_text_vector(dsl_state) do
    name = AshAi.Info.vectorize_full_text_name!(dsl_state)

    embedding_model = AshAi.Info.vectorize_embedding_model!(dsl_state)

    case AshAi.Info.vectorize_full_text_text(dsl_state) do
      {:ok, _fun} ->
        case AshAi.Info.vectorize_strategy!(dsl_state) do
          :after_action ->
            dsl_state
            |> add_new_attribute(name, :vector,
              constraints: [dimensions: embedding_model.dimensions()],
              select_by_default?: false
            )

          _ ->
            # TODO
            raise "unreachable"
        end

      _ ->
        {:ok, dsl_state}
    end
  end
end
