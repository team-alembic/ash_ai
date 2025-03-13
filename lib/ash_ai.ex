defmodule AshAi do
  @moduledoc """
  Documentation for `AshAi`.
  """

  alias LangChain.Chains.LLMChain

  defstruct []

  @full_text %Spark.Dsl.Section{
    name: :full_text,
    imports: [Ash.Expr],
    schema: [
      name: [
        type: :atom,
        default: :full_text_vector,
        doc: "The name of the attribute to store the text vector in"
      ],
      used_attributes: [
        type: {:list, :atom},
        doc: "If set, a vector is only regenerated when these attributes are changed"
      ],
      text: [
        type: {:fun, 1},
        required: true,
        doc:
          "A function or expr that takes a list of records and computes a full text string that will be vectorized. If given an expr, use `atomic_ref` to refer to new values, as this is set as an atomic update."
      ]
    ]
  }

  @vectorize %Spark.Dsl.Section{
    name: :vectorize,
    sections: [
      @full_text
    ],
    schema: [
      attributes: [
        type: :keyword_list,
        doc:
          "A keyword list of attributes to vectorize, and the name of the attribute to store the vector in",
        default: []
      ],
      strategy: [
        type: {:one_of, [:after_action]},
        default: :after_action,
        doc:
          "How to compute the vector. Only `after_action` is supported, but eventually `ash_oban` will be supported as well"
      ]
    ]
  }

  defmodule ExposedResource do
    @moduledoc "An action exposed to LLM agents"
    defstruct [:resource, actions: []]
  end

  @expose_resource %Spark.Dsl.Entity{
    name: :expose_resource,
    target: ExposedResource,
    schema: [
      resource: [type: {:spark, Ash.Resource}, required: true],
      actions: [type: {:list, :atom}]
    ],
    args: [:resource, :actions]
  }

  @agents %Spark.Dsl.Section{
    name: :agents,
    entities: [
      @expose_resource
    ]
  }

  use Spark.Dsl.Extension,
    sections: [@agents, @vectorize],
    imports: [AshAi.Actions],
    transformers: [AshAi.Transformers.Vectorize]

  defimpl Jason.Encoder, for: OpenApiSpex.Schema do
    def encode(value, opts) do
      OpenApiSpex.OpenApi.to_map(value) |> Jason.Encoder.Map.encode(opts)
    end
  end

  defmodule Options do
    use Spark.Options.Validator,
      schema: [
        actions: [
          type: {:wrap_list, {:tuple, [{:spark, Ash.Resource}, :atom]}},
          doc: """
          A set of {Resource, :action} pairs, or `{Resource, :*}` for all actions.
          """
        ],
        exclude_actions: [
          type: {:wrap_list, {:tuple, [{:spark, Ash.Resource}, :atom]}},
          doc: """
          A set of {Resource, :action} pairs, or `{Resource, :*}` to be excluded from the added actions.
          """
        ],
        actor: [
          type: :any,
          doc: "The actor performing any actions."
        ],
        messages: [
          type: {:list, :map},
          default: [],
          doc: """
          Used to provide conversation history.
          """
        ],
        otp_app: [
          type: :atom,
          doc: "If present, allows discovering resource actions automatically."
        ],
        system_prompt: [
          type: {:fun, 1},
          doc: """
          A system prompt that takes the provided options and returns a system prompt.

          You will want to include something like the actor's id if you are chatting as an
          actor.
          """
        ]
      ]
  end

  def functions(opts) do
    opts
    |> actions()
    |> Enum.map(fn {domain, resource, action} ->
      function(domain, resource, action)
    end)
  end

  # def ask_about_actions_function(otp_app_or_actions) do
  # end

  def iex_chat(lang_chain, opts \\ []) do
    opts = Options.validate!(opts)

    messages =
      case opts.system_prompt do
        :none ->
          []

        nil ->
          [
            LangChain.Message.new_system!("""
            You are a helpful assistant.
            Your purpose is to operate the application on behalf of the user.
            """)
          ]

        system_prompt ->
          [LangChain.Message.new_system!(system_prompt)]
      end

    handler = %{
      on_llm_new_delta: fn _model, data ->
        # we received a piece of data
        IO.write(data.content)
      end,
      on_message_processed: fn _chain, _data ->
        # the message was assembled and is processed
        IO.write("\n--\n")
      end
    }

    lang_chain
    |> LLMChain.add_messages(messages)
    |> setup_ash_ai(opts)
    |> LLMChain.add_callback(handler)
    |> then(fn llm_chain ->
      if opts.actor do
        LLMChain.update_custom_context(llm_chain, %{actor: opts.actor})
      else
        llm_chain
      end
    end)
    |> run_loop(true)
  end

  @doc """
  Adds the requisite context and tool calls to allow an agent to interact with your app.


  """
  def setup_ash_ai(lang_chain, opts \\ []) do
    opts = Options.validate!(opts)

    tools = functions(opts)

    if Enum.count_until(tools, 32) == 32 do
      raise "can't do more than 32 tools right now"
      # TODO: select_and_execute_action()
    end

    lang_chain
    |> LLMChain.add_tools(tools)
  end

  defp run_loop(chain, first? \\ false) do
    chain
    |> LLMChain.run(mode: :while_needs_response)
    |> case do
      {:ok,
       %LangChain.Chains.LLMChain{
         last_message: %{content: content}
       } = new_chain} ->
        if !first? && !Map.get(new_chain.llm, :stream) do
          IO.puts(content)
        end

        user_message = Mix.shell().prompt("> ")

        new_chain
        |> LLMChain.add_messages([LangChain.Message.new_user!(user_message)])
        |> run_loop()

      {:error, error} ->
        raise "Something went wrong:\n #{Exception.format(:error, error)}"
    end
  end

  defp parameter_schema(_domain, resource, action) do
    AshJsonApi.OpenApi.write_attributes(
      resource,
      action.arguments,
      action,
      %{type: :action, route: "/"},
      :json
    )
    |> then(fn attrs ->
      %{
        type: :object,
        properties:
          %{
            input: %{
              type: :object,
              properties: attrs
            }
          }
          |> add_action_specific_properties(resource, action)
      }
    end)
    |> Jason.encode!()
    |> Jason.decode!()
  end

  defp function(domain, resource, action) do
    name =
      "#{String.replace(inspect(domain), ".", "_")}-#{String.replace(inspect(resource), ".", "_")}-#{action.name}"

    description =
      action.description ||
        "Call the #{action.name} action on the #{inspect(resource)} resource"

    LangChain.Function.new!(%{
      name: name,
      description: description,
      parameters_schema: parameter_schema(domain, resource, action),
      function: fn arguments, context ->
        actor = context[:actor]

        try do
          case action.type do
            :read ->
              sort =
                case arguments["sort"] do
                  sort when is_list(sort) ->
                    Enum.map(sort, fn map ->
                      case map["direction"] || "asc" do
                        "asc" -> map["field"]
                        "desc" -> "-#{map["field"]}"
                      end
                    end)

                  nil ->
                    []
                end
                |> Enum.join(",")

              resource
              |> Ash.Query.limit(arguments["limit"] || 25)
              |> Ash.Query.offset(arguments["offset"])
              |> then(fn query ->
                if sort != "" do
                  Ash.Query.sort_input(query, sort)
                else
                  query
                end
              end)
              |> then(fn query ->
                if Map.has_key?(arguments, "filter") do
                  Ash.Query.filter_input(query, arguments["filter"])
                else
                  query
                end
              end)
              |> Ash.Query.for_read(action.name, arguments["input"] || %{},
                domain: domain,
                actor: actor
              )
              |> Ash.Actions.Read.unpaginated_read(action)
              |> case do
                {:ok, value} ->
                  value

                {:error, error} ->
                  raise Ash.Error.to_error_class(error)
              end
              |> then(fn result ->
                result
                |> AshJsonApi.Serializer.serialize_value({:array, resource}, [], domain)
                |> Jason.encode!()
                |> then(&{:ok, &1, result})
              end)

            :update ->
              pkey =
                Map.new(Ash.Resource.Info.primary_key(resource), fn key ->
                  {key, arguments[to_string(key)]}
                end)

              resource
              |> Ash.get!(pkey)
              |> Ash.Changeset.for_update(action.name, arguments["input"],
                domain: domain,
                actor: actor
              )
              |> Ash.update!()
              |> then(fn result ->
                result
                |> AshJsonApi.Serializer.serialize_value(resource, [], domain)
                |> Jason.encode!()
                |> then(&{:ok, &1, result})
              end)

            :destroy ->
              pkey =
                Map.new(Ash.Resource.Info.primary_key(resource), fn key ->
                  {key, arguments[to_string(key)]}
                end)

              resource
              |> Ash.get!(pkey)
              |> Ash.Changeset.for_destroy(action.name, arguments["input"],
                domain: domain,
                actor: actor
              )
              |> Ash.destroy!()
              |> then(fn result ->
                result
                |> AshJsonApi.Serializer.serialize_value(resource, [], domain)
                |> Jason.encode!()
                |> then(&{:ok, &1, result})
              end)

            :create ->
              resource
              |> Ash.Changeset.for_create(action.name, arguments["input"],
                domain: domain,
                actor: actor
              )
              |> Ash.create!()
              |> then(fn result ->
                result
                |> AshJsonApi.Serializer.serialize_value(resource, [], domain)
                |> Jason.encode!()
                |> then(&{:ok, &1, result})
              end)

            :action ->
              resource
              |> Ash.ActionInput.for_action(action.name, arguments["input"],
                domain: domain,
                actor: actor
              )
              |> Ash.run_action!()
              |> then(fn result ->
                if action.returns do
                  result
                  |> AshJsonApi.Serializer.serialize_value(action.returns, [], domain)
                  |> Jason.encode!()
                else
                  "success"
                end
                |> then(&{:ok, &1, result})
              end)
          end
        rescue
          error ->
            {:error,
             Jason.encode!(
               AshJsonApi.Error.to_json_api_errors(domain, resource, error, action.type)
             )}
        end
      end
    })
  end

  defp add_action_specific_properties(properties, resource, %{type: :read}) do
    Map.merge(properties, %{
      filter: %{
        type: :object,
        description: "Filter results",
        # querying is complex, will likely need to be a two step process
        # i.e first decide to query, and then provide it with a function to call
        # that has all the options Then the filter object can be big & expressive.
        properties:
          Ash.Resource.Info.fields(resource, [:attributes, :calculations])
          |> Enum.filter(&(&1.public? && &1.filterable?))
          |> Enum.map(fn field ->
            {field.name, AshJsonApi.OpenApi.raw_filter_type(field, resource)}
          end)
          |> Enum.into(%{})
          |> Jason.encode!()
          |> Jason.decode!()
      },
      limit: %{
        type: :integer,
        description: "The maximum number of records to return",
        default: 25
      },
      offset: %{
        type: :integer,
        description: "The number of records to skip",
        default: 0
      },
      sort: %{
        type: :array,
        items: %{
          type: :object,
          properties:
            %{
              field: %{
                type: :string,
                description: "The field to sort by",
                enum:
                  Ash.Resource.Info.fields(resource, [
                    :attributes,
                    :calculations,
                    :aggregates
                  ])
                  |> Enum.filter(&(&1.public? && &1.sortable?))
                  |> Enum.map(& &1.name)
              },
              direction: %{
                type: :string,
                description: "The direction to sort by",
                enum: ["asc", "desc"]
              }
            }
            |> add_input_for_fields(resource)
        }
      }
    })
  end

  defp add_action_specific_properties(properties, resource, %{type: type})
       when type in [:update, :destroy] do
    pkey = Map.new(Ash.Resource.Info.primary_key(resource), fn key -> {key, %{type: :string}} end)

    Map.merge(properties, pkey)
  end

  defp add_action_specific_properties(properties, _resource, _action), do: properties

  defp add_input_for_fields(sort_obj, resource) do
    resource
    |> Ash.Resource.Info.fields([
      :calculations
    ])
    |> Enum.filter(&(&1.public? && &1.sortable? && !Enum.empty?(&1.arguments)))
    |> case do
      [] ->
        sort_obj

      fields ->
        input_for_fields =
          %{
            type: :object,
            additonalProperties: false,
            properties:
              Map.new(fields, fn field ->
                inputs =
                  Enum.map(field.arguments, fn argument ->
                    {argument.name,
                     AshJsonApi.OpenApi.resource_write_attribute_type(argument, :create)}
                  end)

                required =
                  Enum.flat_map(field.arguments, fn argument ->
                    if argument.allow_nil? do
                      []
                    else
                      [argument.name]
                    end
                  end)

                {field.name,
                 %{
                   type: :object,
                   properties: Map.new(inputs),
                   required: required,
                   additionalProperties: false
                 }}
              end)
          }

        Map.put(sort_obj, :input_for_fields, input_for_fields)
    end
  end

  @doc false
  def actions(opts) when is_list(opts) do
    actions(Options.validate!(opts))
  end

  def actions(opts) do
    if opts.actions do
      Enum.flat_map(opts.actions, fn
        {resource, actions} ->
          if !Ash.Resource.Info.domain(resource) do
            raise "Cannot use an ash resource that does not have a domain"
          end

          if actions == :* do
            Enum.map(Ash.Resource.Info.actions(resource), fn action ->
              {Ash.Resource.Info.domain(resource), resource, action}
            end)
          else
            Enum.map(List.wrap(actions), fn action ->
              action_struct = Ash.Resource.Info.action(resource, action)

              unless action_struct do
                raise "Action #{inspect(action)} does not exist on resource #{inspect(resource)}"
              end

              {Ash.Resource.Info.domain(resource), resource, action_struct}
            end)
          end
      end)
    else
      if !opts.otp_app do
        raise "Must specify `otp_app` if you do not specify `actions`"
      end

      for domain <- Application.get_env(opts.otp_app, :ash_domains) || [],
          resource <- Ash.Domain.Info.resources(domain),
          action <- Ash.Resource.Info.actions(resource),
          AshAi in Spark.extensions(resource),
          AshAi.Info.exposes?(domain, resource, action.name),
          can?(opts.actor, domain, resource, action) do
        {domain, resource, action}
      end
      |> Enum.uniq_by(fn {_domain, resource, action} ->
        {resource, action}
      end)
      |> Enum.filter(fn {_domain, resource, action} ->
        if opts.actions do
          Enum.any?(opts.actions, fn {allowed_resource, allowed_actions} ->
            allowed_resource == resource and (allowed_actions == :* or action in allowed_actions)
          end)
        else
          true
        end
      end)
    end
    |> then(fn actions ->
      if is_list(opts.exclude_actions) do
        Enum.reject(actions, fn {_, resource, action} ->
          {resource, action.name} in opts.exclude_actions
        end)
      else
        actions
      end
    end)
  end

  defp can?(actor, domain, resource, action) do
    Ash.can?({resource, action}, actor, domain: domain, maybe_is: true, run_queries?: false)
  end
end
