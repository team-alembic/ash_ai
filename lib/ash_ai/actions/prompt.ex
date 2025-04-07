defmodule AshAi.Actions.Prompt do
  @prompt_template """
  You are responsible for performing the `<%= @input.action.name %>` action.

  <%= if @input.action.description do %>
  # Description
  <%= @input.action.description %>
  <% end %>
  <%= for argument <- @input.action.arguments,
      {:ok, value} = Ash.ActionInput.fetch_argument(@input, argument.name),
      {:ok, value} = Ash.Type.dump_to_embedded(argument.type, value, argument.constraints) do %>
  ## <%= argument.name %>
  <%= if argument.description do %>
  ### Description
  <%= argument.description %>
  <% end %>
  ### Value
  <%= Jason.encode!(value) %>
  <% end %>
  """
  @moduledoc """
  A generic action impl that returns structured outputs from an LLM matching the action return. 

  Typically used via `prompt/2`, for example:

  ```elixir
  action :analyze_sentiment, :atom do
    constraints one_of: [:positive, :negative]

    description \"""
    Analyzes the sentiment of a given piece of text to determine if it is overall positive or negative.
    
    Does not consider swear words as inherently negative.
    \"""

    argument :text, :string do
      allow_nil? false
      description "The text for analysis."
    end

    run prompt(
      LangChain.ChatModels.ChatOpenAI.new!(%{ model: "gpt-4o"}),
      # setting `tools: true` allows it to use all exposed tools in your app
      tools: true 
      # alternatively you can restrict it to only a set of tools
      # tools: [:list, :of, :tool, :names]
      # provide an optional prompt, which is an EEx template
      # prompt: "Analyze the sentiment of the following text: <%= @input.arguments.description %>"
    )
  end
  ```

  The first argument to `prompt/2` is the `LangChain` model. It can also be a 2-arity function which will be invoked
  with the input and the context, useful for dynamically selecting the model.

  ## Options

  - `:tools`: A list of tool names to expose to the agent call.
  - `:verbose`: Set to `true` for more output to be logged.
  - `:prompt`: A custom prompt as an `EEx` template. See the prompt section below.

  ## Prompt

  The prompt by default is generated using the action and input descriptions. You can provide your own prompt
  via the `prompt` option which will be able to reference `@input` and `@context`.

  We have found that the "3rd party" style description writing paired with the format we provide by default to be
  a good basis point for LLMs who are meant to accomplish a task. With this in mind, for refining your prompt,
  first try describing via the action description that desired outcome or operating basis of the action, as well
  as how the LLM is meant to use them. State these passively as facts. For example, above we used: "Does not consider swear
  words as inherently negative" instead of instructing the LLM via "Do not consider swear words as inherently negative".

  You are of course free to use any prompting pattern you prefer, but the end result of the above prompting pattern
  leads to having a great description of your actual logic, acting both as documentation and instructions to the 
  LLM that executes the action.

  The default prompt template is:

  ```elixir
  \"""
  #{@prompt_template}
  \"""
  ```
  """
  use Ash.Resource.Actions.Implementation

  alias LangChain.Chains.LLMChain
  alias LangChain.Message

  # sobelow_skip ["RCE.EEx"]
  def run(input, opts, context) do
    llm =
      case opts[:llm] do
        function when is_function(function) ->
          function.(input, context)

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
            nil,
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
      |> then(fn schema ->
        %{
          "strict" => true,
          "schema" => %{
            "type" => "object",
            "properties" => %{"result" => schema},
            "required" => ["result"],
            "additionalProperties" => false
          },
          "name" => "result"
        }
      end)

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

          AshAi.functions(
            otp_app: otp_app,
            exclude_actions: [{input.resource, input.action.name}],
            actor: context.actor,
            tenant: context.tenant
          )

        tools ->
          otp_app =
            Spark.otp_app(input.domain) ||
              Spark.otp_app(input.resource) ||
              raise "otp_app must be configured on the domain or the resource to get access to all tools"

          AshAi.functions(
            tools: List.wrap(tools),
            otp_app: otp_app,
            exclude_actions: [{input.resource, input.action.name}],
            actor: context.actor,
            tenant: context.tenant
          )
      end

    prompt_template = Keyword.get(opts, :prompt, @prompt_template)

    prompt = EEx.eval_string(prompt_template, assigns: [input: input, context: context])

    messages = [
      Message.new_system!(prompt),
      Message.new_user!("Perform the action.")
    ]

    %{
      llm: llm,
      verbose: opts[:verbose?] || false,
      custom_context: Map.new(Ash.Context.to_opts(context))
    }
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
            _error ->
              {:error, "Invalid LLM response"}
          end
        else
          :ok
        end

      {:error, _, error} ->
        {:error, error}
    end
  end
end
