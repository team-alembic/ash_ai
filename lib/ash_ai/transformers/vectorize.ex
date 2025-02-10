defmodule AshAi.Transformers.Vectorize do
  use Spark.Dsl.Transformer

  import Spark.Dsl.Builder
  import Ash.Resource.Builder

  def after?(_), do: true

  def transform(dsl) do
    if Ash.Resource.Info.data_layer(dsl) != AshPostgres.DataLayer do
      raise "AshAi only currently supports AshPostgres"
    end

    dsl
    |> AshAi.Info.vectorize_attributes!()
    |> Enum.reduce({:ok, dsl}, &vectorize_attribute(&2, &1))
    |> full_text_vector()
    |> update_vectors_action()
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
    dsl_state
    |> add_new_attribute(dest, :vector)
    |> add_new_calculation(
      :"#{dest}_vector_distance",
      :float,
      {AshAi.Calculations.VectorDistance, name: dest},
      public?: true,
      arguments: [
        build_calculation_argument(:query, :string, allow_nil?: false),
        build_calculation_argument(:distance_algorithm, :atom,
          allow_nil?: false,
          default: :l2,
          constraints: [
            one_of: [:l2, :cosine]
          ]
        )
      ]
    )
  end

  defbuilder full_text_vector(dsl_state) do
    name = AshAi.Info.vectorize_full_text_name!(dsl_state)

    case AshAi.Info.vectorize_full_text_text(dsl_state) do
      {:ok, _fun} ->
        case AshAi.Info.vectorize_strategy!(dsl_state) do
          :after_action ->
            dsl_state
            |> add_new_attribute(name, :vector)
            |> add_new_calculation(
              :"#{name}_vector_distance",
              :float,
              {AshAi.Calculations.VectorDistance, name: :"#{name}_vector_distance"},
              public?: true,
              arguments: [
                build_calculation_argument(:query, :string, allow_nil?: false),
                build_calculation_argument(:distance_algorithm, :atom,
                  allow_nil?: false,
                  constraints: [
                    one_of: [:l2, :cosine]
                  ]
                )
              ]
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
