# AshAi

This is a _HIGHLY EXPERIMENTAL_ package. It is 500 lines of code built for a demo.

## Whats in the box

### Expose actions as tool calls

```elixir
defmodule MyApp.Blog do
  agents do
    expose_resource MyApp.Blog.Post, [:read, :create, :publish]
    expose_resource MyApp.Blog.Comment, [:read]
  end
end
```

Expose these actions as tools. When you call `AshAi.setup_ash_ai(chain, opts)`, or `AshAi.iex_chat/2` 
it will add those as tool calls to the agent.

### Prompt-backed actions

Only tested against OpenAI.

This allows defining an action, including input and output types, and delegating the
implementation to an LLM. We use structured outputs to ensure that it always returns
the correct data type. We also derive a default prompt from the action description and 
action inputs.

```elixir
action :analyze_sentiment, :atom do
  constraints one_of: [:positive, :negative]

  description """
  Analyzes the sentiment of a given piece of text to determine if it is overall positive or negative.
  """

  argument :text, :string do
    allow_nil? false
    description "The text for analysis"
  end

  run prompt(
        LangChain.ChatModels.ChatOpenAI.new!(%{
          model: "gpt-4o",
          receive_timeout: :timer.minutes(2)
        }),
        # setting `tools: true` allows it to use all exposed tools in your app
        tools: true 
        # alternatively you can restrict it to only a set of resources/actions
        # tools: [{Resource, :action}, {OtherResource, :action}]
        # provide an optional prompt, which is an EEx template
        # prompt: "Analyze the sentiment of the following text: <%= @input.arguments.description %>"
      )
end
```

### Vectorization

Only supports OpenAI, the details are hard coded currently, and requires setting `OPEN_AI_API_KEY`.

This extension creates a vector search action and also rebuilds and stores a vector on all changes.
This will make your app much slower in its current form. We wille ventually make it work where it triggers an oban
job to do this work after-the-fact.

```elixir
# in a resource

vectorize do
  full_text do
    text(fn record ->
      """
      Name: #{record.name}
      Biography: #{record.biography}
      """
    end)
  end

  attributes(name: :vectorized_name)
end
```

If you are using policies, add a bypass to allow us to update the vector embeddings:

```elixir
bypass AshAi.Checks.ActorIsAshAi do
  authorize_if always()
end
```


## What else ought to happen?

- more action types, like:
  - bulk updates
  - bulk destroys
  - bulk creates.

## Installation

This is not yet available on hex.

```elixir
def deps do
  [
    {:ash_ai, github: "ash-project/ash_ai"}
  ]
end
```

## How to play with it

1. Setup `LangChain`
2. Modify a `LangChain` using `AshAi.setup_ash_ai/2`` or use `AshAi.iex_chat` (see below)
2. Run `iex -S mix` and then run `AshAi.iex_chat` to start chatting with your app.
3. To build your own chat interface, you'll use `AshAi.instruct/2`. See the implementation
   of `AshAi.iex_chat` to see how its done.

## Using AshAi.iex_chat

```elixir
defmodule MyApp.ChatBot do
  alias LangChain.Chains.LLMChain
  alias LangChain.ChatModels.ChatOpenAI

  def iex_chat(actor \\ nil) do
    %{
      llm: ChatOpenAI.new!(%{model: "gpt-4o", stream: true),
      verbose?: true
    }
    |> LLMChain.new!()
    |> AshAi.iex_chat(actor: actor, otp_app: :my_app)
  end
end

# it will use the exposed actions in your domains

agents do
  expose_resource MyApp.MyDomain.MyResource, [:list, :of, :actions]
  expose_resource MyApp.MyDomain.MyResource2, [:list, :of, :actions]
end
```
