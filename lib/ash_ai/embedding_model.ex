defmodule AshAi.EmbeddingModel do
  @moduledoc """
  A behaviour that defines the dimensions of the vector, and how to generate the embedding
  """

  @doc "The dimensions of generated embeddings"
  @callback dimensions :: pos_integer()
  @doc "Generate embeddings for the given list of strings"
  @callback generate([String.t()]) :: {:ok, [binary()]} | {:error, term()}

  defmacro __using__(_) do
    quote do
      @behaviour AshAi.EmbeddingModel
    end
  end
end
