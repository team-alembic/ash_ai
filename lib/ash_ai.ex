defmodule AshAi do
  @moduledoc """
  Documentation for `AshAi`.
  """

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

  use Spark.Dsl.Extension, sections: [@ai_agent]

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
          Your job is to operate the application on behalf of the following actor:

          #{inspect(opts.actor)}

          Do not make assumptions about what they can or cannot do. All actions are secure,
          and will forbid any unauthorized actions.
          """
        else
          """
          Do not make assumptions about what you can or cannot do. All actions are secure,
          and will forbid any unauthorized actions.
          """
        end
      end

    messages =
      opts.messages ++
        [
          OpenaiEx.ChatMessage.developer(system),
          OpenaiEx.ChatMessage.user(prompt)
        ]

    case functions(openai, messages, opts) do
      {message_res, message, messages} when message_res in [:complete, :message] ->
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
        |> call_until_complete(opts.actor, openai, functions, messages, content)
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
         _actor,
         _openai,
         _functions,
         messages,
         content
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
         _actor,
         _openai,
         _functions,
         messages,
         new_content
       ) do
    {:ok, add_to_content(content, new_content), messages ++ [message]}
  end

  defp call_until_complete(%{"choices" => choices}, actor, openai, functions, messages, content) do
    choice = Enum.at(choices, 0)["message"]

    if Enum.empty?(choice["tool_calls"] || []) do
      raise "no tool calls"
    end

    tool_call_results =
      Enum.flat_map(choice["tool_calls"], fn
        %{"function" => %{"name" => "complete"}, "id" => id} = message ->
          [message, tool_call_result("", id, "complete")]

        %{"function" => %{"name" => name, "arguments" => arguments}, "id" => id} ->
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
                |> Ash.Query.limit(arguments["limit"])
                |> Ash.Query.offset(arguments["offset"])
                |> Ash.Query.load(arguments["load"])
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
                |> Ash.read!()
                |> inspect(limit: :infinity)
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
                |> inspect(limit: :infinity)
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
                |> Ash.destroy!()
                |> inspect(limit: :infinity)
                |> tool_call_result(id, name)

              :create ->
                resource
                |> Ash.Changeset.for_create(action.name, arguments["input"],
                  domain: domain,
                  actor: actor
                )
                |> Ash.create!()
                |> inspect(limit: :infinity)
                |> tool_call_result(id, name)
                |> List.wrap()
            end
          rescue
            e ->
              inspect(Exception.format(:error, e, __STACKTRACE__))
              |> tool_call_result(id, name)
              |> List.wrap()
          end
      end)

    messages = messages ++ [choice | tool_call_results]

    case Enum.find(choice["tool_calls"] || [], &(&1["function"]["name"] == "complete")) do
      nil ->
        fn_req =
          OpenaiEx.Chat.Completions.new(
            model: "gpt-4o-mini",
            messages: messages,
            tools: functions,
            tool_choice: "auto"
          )

        openai
        |> OpenaiEx.Chat.Completions.create!(fn_req)
        |> call_until_complete(actor, openai, functions, messages, content)

      _ ->
        {:ok, content, messages}
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

  defp pick_action(actions, openai, messages) do
    if Enum.count_until(actions, @function_limit) == @function_limit do
      actions_map =
        Map.new(actions, fn {domain, resource, action} ->
          {"#{inspect(domain)}.#{inspect(resource)}.#{action.name}", {domain, resource, action}}
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

                  "- #{key}(#{inputs}) | #{action.type} | #{description}"
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

      functions = [select_action(Map.keys(actions_map)), @complete]

      prompt =
        """
        Select from the following actions to take, or call the complete function if there is nothing left or nothing appropriate to do.

        Read actions support being filtered further on input

        Feel free to ask the user clarifying questions before selecting an action if necessary.

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

          {add_to_content(content, arguments["reason"]),
           messages ++ [tool_call_result("", id, "complete")], true, action}

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
                     "complete"
                   )
                 ], done?, action}

            :error ->
              if action do
                {content,
                 messages ++
                   [tool_call_result("", id, "complete")], done?, action}
              else
                text = "No appropriate action could be found to take to fulfill request."

                {add_to_content(content, text),
                 messages ++
                   [tool_call_result(text, id, "complete")], done?, action}
              end
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

  @doc false
  def functions(openai, messages, opts) when is_list(opts) do
    functions(openai, messages, Options.validate!(opts))
  end

  def functions(openai, messages, opts) do
    opts
    |> actions()
    |> pick_action(openai, messages)
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
        # querying is complex, will likely need to be a two step process
        # i.e first decide to query, and then provide it with a function to call
        # that has all the options Then the filter object can be big & expressive.
        properties:
          Ash.Resource.Info.fields(resource, [:attributes])
          |> Enum.filter(& &1.public?)
          |> Enum.map(fn field ->
            {field.name, AshJsonApi.OpenApi.raw_filter_type(field, resource)}
          end)
          |> Enum.into(%{})
      },
      load: %{
        type: :array,
        items: %{
          type: :string,
          enum:
            Ash.Resource.Info.fields(resource, [
              :relationships,
              :calculations,
              :aggregates
            ])
            |> Enum.filter(& &1.public?)
            |> Enum.map(& &1.name)
        }
      },
      limit: %{
        type: :integer,
        description: "The maximum number of records to return",
        default: 10
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
          properties: %{
            field: %{
              type: :string,
              description: "The field to sort by",
              enum:
                Ash.Resource.Info.fields(resource, [
                  :attributes,
                  :calculations,
                  :aggregates
                ])
                |> Enum.filter(& &1.public?)
                |> Enum.map(& &1.name)
            },
            direction: %{
              type: :string,
              description: "The direction to sort by",
              enum: ["asc", "desc"]
            }
          }
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
      |> Enum.take(32)
    end
  end

  defp can?(actor, domain, resource, action) do
    Ash.can?({resource, action}, actor, domain: domain, maybe_is: true, run_queries?: false)
  end
end
