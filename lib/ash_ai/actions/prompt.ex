defmodule AshAi.Actions.Prompt do
  use Ash.Resource.Actions.Implementation

  alias LangChain.Chains.LLMChain
  alias LangChain.Message

  def run(input, opts, context) do
    llm =
      case opts[:llm] do
        function when is_function(function) ->
          function.input(input, context)

        llm ->
          llm
      end

    if !Map.has_key?(llm, :json_schema) do
      raise "Only LLMs that have the `json_schema` can currently be used to run actions"
    end

    json_schema =
      if input.action.returns do
        schema =
          AshJsonApi.OpenApi.resource_write_attribute_type(
            %{name: :result, type: input.action.returns, constraints: input.action.constraints},
            :create
          )

        if input.action.allow_nil? do
          %{"anyOf" => [%{"type" => "null"}, schema]}
        else
          schema
        end
      else
        %{"type" => "null"}
      end
      |> Jason.encode!()
      |> Jason.decode!()
      |> then(
        &%{
          "schema" => %{
            "type" => "object",
            "properties" => %{"result" => &1},
            "required" => ["result"]
          },
          "name" => "result"
        }
      )

    llm =
      Map.merge(llm, %{json_schema: json_schema, json_response: true})

    tools =
      case opts[:tools] do
        nil ->
          []

        true ->
          otp_app =
            Spark.otp_app(input.domain) ||
              Spark.otp_app(input.resource) ||
              raise "otp_app must be configured on the domain or the resource to get access to all tools"

          AshAi.functions(otp_app: otp_app)

        tools ->
          actions =
            Enum.map(tools, fn
              tool when is_atom(tool) ->
                {input.domain, input.resource, tool}

              {resource, tool} ->
                {input.domain, resource, tool}

              {domain, resource, tool} ->
                {domain, resource, tool}
            end)

          AshAi.functions(actions: actions)
      end

    prompt =
      case Keyword.fetch(opts, :prompt) do
        {:ok, value} ->
          EEx.eval_string(value, input: input, context: context)

        _ ->
          """
          You are responsible for performing the `#{input.action.name}` action.

          #{description(input)}
          #{inputs(input)}
          """
      end

    messages = [
      Message.new_system!(prompt),
      Message.new_user!("Perform the action.")
    ]

    %{llm: llm, verbose: opts[:verbose] || false, custom_context: Map.from_struct(context)}
    |> LLMChain.new!()
    |> LLMChain.add_messages(messages)
    |> LLMChain.add_tools(tools)
    |> LLMChain.run(mode: :while_needs_response)
    |> case do
      {:ok,
       %LangChain.Chains.LLMChain{
         last_message: %{content: content}
       }}
      when is_binary(content) ->
        if input.action.returns do
          with {:ok, value} <-
                 Ash.Type.cast_input(
                   input.action.returns,
                   Jason.decode!(content)["result"],
                   input.action.constraints
                 ),
               {:ok, value} <-
                 Ash.Type.apply_constraints(input.action.returns, value, input.action.constraints) do
            {:ok, value}
          else
            _ ->
              {:error, "Invalid LLM response"}
          end
        else
          :ok
        end

      {:error, error} ->
        {:error, error}
    end
  end

  defp description(input) do
    if input.action.description do
      "# Description\n\n#{input.action.description}"
    else
      ""
    end
  end

  defp inputs(%{action: %{arguments: []}}) do
    ""
  end

  defp inputs(%{action: %{arguments: arguments}} = input) do
    arguments
    |> Enum.reduce(%{}, fn argument, acc ->
      with {:ok, value} <- Ash.ActionInput.fetch_argument(input, argument.name),
           {:ok, value} <- Ash.Type.dump_to_embedded(argument.type, value, argument.constraints) do
        Map.put(acc, argument.name, value)
      else
        _ ->
          acc
      end
    end)
    |> Jason.encode!()
  end
end
