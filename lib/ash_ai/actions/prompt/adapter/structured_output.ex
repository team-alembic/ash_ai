defmodule AshAi.Actions.Prompt.Adapter.StructuredOutput do
  @moduledoc """
  An adapter for prompt-backed actions that leverages structured output from LLMs.

  The only currently known service that supports this is OpenAI.
  """
  @behaviour AshAi.Actions.Prompt.Adapter

  alias AshAi.Actions.Prompt.Adapter.Data
  alias LangChain.Chains.LLMChain
  alias LangChain.Message

  def run(%Data{} = data, _opts) do
    if !Map.has_key?(data.llm, :json_schema) do
      raise "Only LLMs that have a `json_schema` field can currently be used with the #{inspect(__MODULE__)} adapter"
    end

    llm =
      Map.merge(data.llm, %{
        json_schema: %{
          "strict" => true,
          "schema" => %{
            "type" => "object",
            "properties" => %{"result" => data.json_schema},
            "required" => ["result"],
            "additionalProperties" => false
          },
          "name" => "result"
        },
        json_response: true
      })

    messages = [
      Message.new_system!(data.system_prompt),
      Message.new_user!(data.user_message)
    ]

    %{
      llm: llm,
      verbose: data.verbose?,
      custom_context: Map.new(Ash.Context.to_opts(data.context))
    }
    |> LLMChain.new!()
    |> LLMChain.add_messages(messages)
    |> LLMChain.add_tools(data.tools)
    |> LLMChain.run(mode: :while_needs_response)
    |> case do
      {:ok,
       %LangChain.Chains.LLMChain{
         last_message: %{content: content}
       }}
      when is_binary(content) ->
        with {:ok, decoded} <- Jason.decode(content),
             {:ok, value} <-
               Ash.Type.cast_input(
                 data.input.action.returns,
                 decoded["result"],
                 data.input.action.constraints
               ),
             {:ok, value} <-
               Ash.Type.apply_constraints(
                 data.input.action.returns,
                 value,
                 data.input.action.constraints
               ) do
          {:ok, value}
        else
          _error ->
            {:error, "Invalid LLM response"}
        end

      {:error, _, error} ->
        {:error, error}
    end
  end
end
