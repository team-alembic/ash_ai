defmodule AshAi do
  @moduledoc """
  Documentation for `AshAi`.
  """

  defstruct []

  @ai_agent %Spark.Dsl.Section{
    name: :ai_agent,
    schema: [
      expose: [
        type: {:or, [{:list, :atom}, {:literal, :*}]},
        doc: "The list of actions to expose to the agent, or :* for everything",
        default: []
      ]
    ]
  }

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

  use Spark.Dsl.Extension,
    sections: [@ai_agent, @vectorize],
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

          By default, the first 32 actions that we find are used.
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

  @doc """
  Chat with the AI in IEx.

  See `instruct/2` for available options.
  """
  def iex_chat(prompt, opts \\ []) do
    {prompt, opts} =
      if Keyword.keyword?(prompt) do
        {nil, prompt}
      else
        {prompt, opts}
      end

    opts = Options.validate!(opts)

    if is_nil(prompt) do
      IO.puts("Hello!")

      case String.trim(Mix.shell().prompt("❯ ")) do
        "" ->
          iex_chat("", opts)

        quit when quit in ["quit", "exit", "stop", "n"] ->
          :done

        message ->
          instruct(message, opts)
      end
    else
      case instruct(prompt, opts) do
        {:ok, response, messages} ->
          IO.puts(String.trim(response))

          case String.trim(Mix.shell().prompt("❯ ")) do
            "" ->
              iex_chat("", %{opts | messages: messages})

            quit when quit in ["quit", "exit", "stop", "n"] ->
              :done

            message ->
              instruct(message, %{opts | messages: messages})
          end
      end
    end
    |> case do
      :done ->
        :done

      {:ok, last_message, messages} ->
        IO.puts(String.trim(last_message || ""))

        case String.trim(Mix.shell().prompt("❯ ")) do
          quit when quit in ["quit", "exit", "stop", "n"] ->
            :done

          message ->
            iex_chat(
              message,
              %{opts | messages: messages ++ [OpenaiEx.ChatMessage.user(last_message)]}
            )
        end
    end
  end

  def instruct!(prompt, opts \\ []) do
    {:ok, res, _} = instruct(prompt, opts)
    res
  end

  def instruct(prompt, opts \\ []) do
    opts = Options.validate!(opts)

    apikey = System.fetch_env!("OPEN_AI_API_KEY")
    openai = OpenaiEx.new(apikey)

    system =
      if opts.system_prompt do
        opts.system_prompt.(opts)
      else
        if opts.actor do
          """
          Your job is to operate the a

          #{inspect(opts.actor)}

          Do not make assumptions about what they can or cannot do. All actions are secure,
          and will forbid any unauthorized actions.

          When searching for similarity, prefer vector searching before other methods of searching,
          and prefer full text if that makes sense.
          """
        else
          """
          Do not make assumptions about what you can or cannot do. All actions are secure,
          and will forbid any unauthorized actions.

          When searching for similarity, prefer vector searching before other methods of searching,
          and prefer full text if that makes sense.
          """
        end
      end

    messages =
      opts.messages ++
        [
          OpenaiEx.ChatMessage.developer(system),
          OpenaiEx.ChatMessage.user(prompt)
        ]

    top_loop(openai, messages, opts)
  end

  defp top_loop(openai, messages, opts) do
    case functions(openai, messages, opts) do
      {:complete, message, messages} ->
        {:ok, message, messages}

      {:message, nil, messages} ->
        top_loop(openai, messages, opts)

      {:message, message, messages} ->
        {:ok, message, messages}

      {:functions, [%{function: %{name: "complete"}}]} ->
        message = "I could find no actions available or appropriate to take in this situation."
        {:ok, message, messages ++ [OpenaiEx.ChatMessage.assistant(message)]}

      {:functions, content, functions, messages} ->
        fn_req =
          OpenaiEx.Chat.Completions.new(
            model: "gpt-4o-mini",
            messages: messages,
            tools: functions,
            tool_choice: "auto"
          )

        openai
        |> OpenaiEx.Chat.Completions.create!(fn_req)
        |> call_until_complete(openai, messages, content, opts)
    end
  end

  defp call_until_complete(
         %{
           "choices" => [
             %{
               "message" =>
                 %{
                   "tool_calls" => [
                     %{
                       "id" => id,
                       "function" => %{
                         "name" => "complete",
                         "arguments" => arguments
                       }
                     }
                     | _
                   ]
                 } = message
             }
             | _
           ]
         },
         _openai,
         messages,
         content,
         _opts
       ) do
    arguments = Jason.decode!(arguments)

    {:ok, add_to_content(content, arguments["message"]),
     messages ++ [message, tool_call_result("", id, "complete")]}
  end

  defp call_until_complete(
         %{
           "choices" => [
             %{"finish_reason" => "stop", "message" => %{"content" => content} = message}
           ]
         },
         _openai,
         messages,
         new_content,
         _opts
       ) do
    {:ok, add_to_content(content, new_content), messages ++ [message]}
  end

  defp call_until_complete(
         %{"choices" => choices},
         openai,
         messages,
         content,
         opts
       ) do
    choice = Enum.at(choices, 0)["message"]

    if Enum.empty?(choice["tool_calls"] || []) do
      raise "no tool calls"
    end

    tool_call_results =
      Enum.flat_map(choice["tool_calls"], fn
        %{"function" => %{"name" => "complete"}, "id" => id} = message ->
          [message, tool_call_result("", id, "complete")]

        %{"function" => %{"name" => name, "arguments" => arguments}, "id" => id} ->
          call_action(name, arguments, opts, id, name)
      end)

    messages = messages ++ [choice | tool_call_results]

    case Enum.find(choice["tool_calls"] || [], &(&1["function"]["name"] == "complete")) do
      nil ->
        top_loop(openai, messages, opts)

      _ ->
        {:ok, content, messages}
    end
  end

  defp call_action(name, arguments, opts, id, name) do
    actor = opts.actor

    try do
      arguments = Jason.decode!(arguments)

      [domain, resource, action] = String.split(name, "-")

      domain = Module.concat([String.replace(domain, "_", ".")])
      resource = Module.concat([String.replace(resource, "_", ".")])

      action =
        Ash.Resource.Info.actions(resource)
        |> Enum.find(fn action_struct ->
          to_string(action_struct.name) == action
        end)

      # make this JSON!
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
          |> Ash.Query.limit(arguments["limit"] || 100)
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
          |> AshJsonApi.Serializer.serialize_value({:array, resource}, [], domain)
          |> Jason.encode!()
          |> tool_call_result(id, name)
          |> List.wrap()

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
          |> AshJsonApi.Serializer.serialize_value(resource, [], domain)
          |> Jason.encode!()
          |> tool_call_result(id, name)
          |> List.wrap()

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
          |> AshJsonApi.Serializer.serialize_value(resource, [], domain)
          |> Jason.encode!()
          |> tool_call_result(id, name)

        :create ->
          resource
          |> Ash.Changeset.for_create(action.name, arguments["input"],
            domain: domain,
            actor: actor
          )
          |> Ash.create!()
          |> AshJsonApi.Serializer.serialize_value(resource, [], domain)
          |> Jason.encode!()
          |> tool_call_result(id, name)
          |> List.wrap()

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
              |> tool_call_result(id, name)
              |> List.wrap()
            else
              :ok
            end
          end)
      end
    rescue
      e ->
        Exception.format(:error, e, __STACKTRACE__)
        |> inspect()
        |> tool_call_result(id, name)
        |> List.wrap()
    end
  end

  defp tool_call_result(result, id, name) do
    OpenaiEx.ChatMessage.tool(id, name, result)
  end

  # Seems like we should just always have them select an action first. Its a simpler architecture
  @function_limit 1

  @complete %{
    type: :function,
    function: %{
      name: "complete",
      description: "Call this when the users original request has been fulfilled",
      parameters: %{
        type: :object,
        properties: %{
          message: %{
            type: :string,
            description:
              "The message to the user finalizing completion of the task, explaining what was done."
          }
        }
      }
    }
  }

  defp pick_action(actions, openai, messages, opts) do
    if Enum.count_until(actions, @function_limit) == @function_limit do
      actions_map =
        Map.new(actions, fn {domain, resource, action} ->
          name =
            "#{String.replace(inspect(domain), ".", "_")}-#{String.replace(inspect(resource), ".", "_")}-#{action.name}"

          {name, {domain, resource, action}}
        end)

      action_options =
        actions_map
        |> Enum.group_by(fn {_key, {domain, _resource, _action}} -> domain end)
        |> Enum.map(fn {domain, domain_actions} ->
          resources =
            domain_actions
            |> Enum.group_by(fn {_key, {_domain, resource, _action}} -> resource end)
            |> Enum.map(fn {resource, resource_actions} ->
              action_descriptions =
                Enum.map(resource_actions, fn {key, {_domain, _resource, action}} ->
                  description =
                    action.description ||
                      "Call the #{action.name} action on the #{inspect(resource)} resource"

                  inputs =
                    Ash.Resource.Info.action_inputs(resource, action)
                    |> Enum.filter(&is_atom/1)
                    |> Enum.map(fn name ->
                      attr =
                        Enum.find(action.arguments, &(&1.name == name)) ||
                          Ash.Resource.Info.attribute(resource, name)

                      "#{name} :: #{inspect(attr.type)}"
                    end)
                    |> Enum.join(", ")

                  return =
                    case action.type do
                      :action ->
                        action.returns || :ok

                      :read ->
                        "#{inspect(resource)}[]"

                      _ ->
                        inspect(resource)
                    end

                  "- `#{action.type}`: #{key}(#{inputs}) :: #{return} | #{description}"
                end)
                |> Enum.join("\n")

              """
              ### #{inspect(resource)}
              #{action_descriptions}
              """
            end)
            |> Enum.join("\n\n")

          """
          ## #{inspect(domain)}
          #{resources}
          """
        end)
        |> Enum.join("\n\n")

      functions = [
        select_action(Map.keys(actions_map)),
        ask_about_action(Map.keys(actions_map)),
        @complete
      ]

      prompt =
        """
        Do one of:

        - Ask the system for more information on one of the below actions. 
          Especially useful for read actions to see what kind of filters,
          sorts and other options are at your disposal. Do not ask the user for permission
          to do this, just do it if you want to. (`ask_about_action` tool call)

        - Select from the below actions to take. Remember: ALL FILTERED FIELDS
          MUST INCLUDE A COMPARISON PREDICATE like `eq` or `greater_than`.
          (`select_action` tool call)
          
        - call the complete function if there is nothing left or appropriate to do.
        - respond to the user to do things like ask clarifying questions, using no tools

        #{action_options}
        """

      messages = messages ++ [OpenaiEx.ChatMessage.developer(prompt)]

      fn_req =
        OpenaiEx.Chat.Completions.new(
          model: "gpt-4o-mini",
          messages: messages,
          tools: functions,
          tool_choice: "auto"
        )

      resp =
        openai
        |> OpenaiEx.Chat.Completions.create!(fn_req)

      choice = Enum.at(resp["choices"], 0)["message"]

      messages = messages ++ [choice]

      choice["tool_calls"]
      |> Kernel.||([])
      |> Enum.map(fn
        %{"function" => %{"name" => name}} = call ->
          # sometimes it thinks it can call these again when
          # it was not presented with those options
          # we pretend that it just asked for info
          case Map.fetch(actions_map, name) do
            {:ok, _} ->
              %{
                call
                | "function" => %{
                    "name" => "ask_about_action",
                    "arguments" =>
                      Jason.encode!(%{
                        "action" => name
                      })
                  }
              }

            _ ->
              call
          end
      end)
      |> Enum.reduce({choice["content"], messages, false, nil}, fn
        %{
          "id" => id,
          "function" => %{
            "name" => "complete",
            "arguments" => arguments
          }
        },
        {content, messages, _done?, action} ->
          arguments = Jason.decode!(arguments)

          {add_to_content(content, arguments["message"]),
           messages ++ [tool_call_result("", id, "complete")], true, action}

        %{
          "id" => id,
          "function" => %{"name" => "ask_about_action", "arguments" => arguments}
        },
        {content, messages, done?, action} ->
          arguments = Jason.decode!(arguments)

          case Map.fetch(actions_map, arguments["action"]) do
            {:ok, {domain, resource, found_action}} ->
              {content,
               messages ++
                 [
                   tool_call_result(
                     """
                     schema for action: #{arguments["action"]}:

                     #{Jason.encode!(function(domain, resource, found_action))}
                     """,
                     id,
                     "ask_about_action"
                   )
                 ], done?, action}

            :error ->
              text = "No such action: #{arguments["action"]}"

              {add_to_content(content, text),
               messages ++
                 [tool_call_result(text, id, "ask_about_action")], done?, action}
          end

        %{
          "id" => id,
          "function" => %{"name" => "select_action", "arguments" => arguments}
        },
        {content, messages, done?, action} ->
          arguments = Jason.decode!(arguments)

          case Map.fetch(actions_map, arguments["action"]) do
            {:ok, action} ->
              {content,
               messages ++
                 [
                   tool_call_result(
                     "action selected: #{arguments["action"]}: #{arguments["reason"]}",
                     id,
                     "select_action"
                   )
                 ], done?, action}

            :error ->
              if action do
                {content,
                 messages ++
                   [tool_call_result("", id, "select_action")], done?, action}
              else
                text = "No appropriate action could be found to take to fulfill request."

                {add_to_content(content, text),
                 messages ++
                   [tool_call_result(text, id, "complete")], done?, action}
              end
          end

        %{
          "id" => id,
          "function" => %{"name" => name, "arguments" => arguments}
        },
        {content, messages, done?, action} ->
          case Map.fetch(actions_map, arguments["action"]) do
            {:ok, {_domain, _resource, _action}} ->
              call_action(name, arguments, opts, id, name)

            _ ->
              text = "Not an available action in this context"

              {add_to_content(content, text),
               messages ++
                 [tool_call_result(text, id, "complete")], done?, action}
          end
      end)
      |> case do
        {content, messages, _, action} when not is_nil(action) ->
          {:chosen, content, action, messages}

        {content, messages, true, _} ->
          {:complete, content, messages}

        {content, messages, false, _} ->
          {:message, content, messages}
      end
    else
      {:no_need, actions}
    end
  end

  defp add_to_content(v, new_content) when v in [nil, ""] do
    new_content
  end

  defp add_to_content(content, new_content) when new_content in [nil, ""] do
    content
  end

  defp add_to_content(content, new_content) do
    content <> "\n\n" <> new_content
  end

  defp select_action(options) do
    %{
      type: :function,
      function: %{
        name: "select_action",
        description: "Call this to select an action to perform.",
        parameters: %{
          type: :object,
          properties: %{
            action: %{
              type: :string,
              description: "The action you wish to take",
              enum: options
            },
            reason: %{
              type: :string,
              description: "The reason you wish to take this action"
            }
          }
        }
      }
    }
  end

  defp ask_about_action(options) do
    %{
      type: :function,
      function: %{
        name: "ask_about_action",
        description: "Call this to see the full schema for a given action.",
        parameters: %{
          type: :object,
          properties: %{
            action: %{
              type: :string,
              description: "The action you wish to ask about",
              enum: options
            }
          }
        }
      }
    }
  end

  @doc false
  def functions(openai, messages, opts) when is_list(opts) do
    functions(openai, messages, Options.validate!(opts))
  end

  def functions(openai, messages, opts) do
    opts
    |> actions()
    |> pick_action(openai, messages, opts)
    |> case do
      {:message, message, messages} ->
        {:message, message, messages}

      {:chosen, content, {domain, resource, action}, messages} ->
        {:functions, content, [function(domain, resource, action), @complete], messages}

      {:complete, message, messages} ->
        {:complete, message, messages}

      {:no_need, actions} ->
        Enum.map(actions, fn {domain, resource, action} ->
          function(domain, resource, action)
        end)
        |> Enum.concat([@complete])
        |> then(&{:functions, "", &1, messages})
    end
  end

  defp function(domain, resource, action) do
    inputs =
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

    name =
      "#{String.replace(inspect(domain), ".", "_")}-#{String.replace(inspect(resource), ".", "_")}-#{action.name}"

    description =
      action.description ||
        "Call the #{action.name} action on the #{inspect(resource)} resource"

    %{
      type: :function,
      function: %{
        name: name,
        description: description,
        parameters: inputs |> Jason.decode!()
      }
    }
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
        default: 100
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
      Enum.flat_map(opts.actions, fn {resource, actions} ->
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
          action.name in AshAi.Info.ai_agent_expose!(resource),
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
  end

  defp can?(actor, domain, resource, action) do
    Ash.can?({resource, action}, actor, domain: domain, maybe_is: true, run_queries?: false)
  end
end
