# Ash AI

## `mix ash_ai.gen.chat`

This is a new and experimental tool to generate a chat feature for your Ash & Phoenix application. It is backed by `ash_oban` and `ash_postgres`, using `pub_sub` to stream messages to the client. This is primarily a tool to get started with chat features and is by no means intended to handle very case you can come up with.

To get started:
```
mix ash_ai.gen.chat --live
```

The `--live` flag indicates that you wish to generate liveviews in addition to the chat resources.

It currently requires a `user` resource to exist. If your `user` resource is not called `<YourApp>.Accounts.User`, provide a custom user resource with the `--user`
flag.

To try it out from scratch:

```sh
mix igniter.new my_app \
  --with phx.new \
  --install ash,ash_postgres,ash_phoenix \
  --install ash_authentication_phoenix,ash_oban \
  --install ash_ai@github:ash-project/ash_ai \
  --auth-strategy password
```

and then run:

```sh
mix ash_ai.gen.chat --live
```

You can then start your server and visit `http://localhost:4000/chat` to see the chat feature in action. You will be prompted to register first and sign in the first time.

## Expose actions as tool calls

```elixir
defmodule MyApp.Blog do
  use Ash.Domain, extensions: [AshAi]

  tools do
    tool :read_posts, MyApp.Blog.Post, :read
    tool :create_post, MyApp.Blog.Post, :create
    tool :publish_post, MyApp.Blog.Post, :publish
    tool :read_comments, MyApp.Blog.Commonet, :read
  end
end
```

Expose these actions as tools. When you call `AshAi.setup_ash_ai(chain, opts)`, or `AshAi.iex_chat/2`
it will add those as tool calls to the agent.

## Prompt-backed actions

Only tested against OpenAI.

This allows defining an action, including input and output types, and delegating the
implementation to an LLM. We use structured outputs to ensure that it always returns
the correct data type. We also derive a default prompt from the action description and
action inputs. See `AshAi.Actions.Prompt` for more information.

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

## Vectorization

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

  # See the section below on defining an embedding model
  embedding_model MyApp.OpenAiEmbeddingModel
end
```

If you are using policies, add a bypass to allow us to update the vector embeddings:

```elixir
bypass AshAi.Checks.ActorIsAshAi do
  authorize_if always()
end
```

### Embedding Models

Embedding models are modules that are in charge of defining what the dimensions
are of a given vector and how to generate one. This example uses `Req` to
generate embeddings using `OpenAi`. To use it, you'd need to install `req`
(`mix igniter.install req`).

```elixir
defmodule Tunez.OpenAIEmbeddingModel do
  use AshAi.EmbeddingModel

  @impl true
  def dimensions(_opts), do: 3072

  @impl true
  def generate(texts, _opts) do
    apikey = System.fetch_env!("OPEN_AI_API_KEY")

    headers = [
      {"Authorization", "Bearer #{api_key}"},
      {"Content-Type", "application/json"}
    ]

    body = %{
      "input" => texts,
      "model" => "text-embedding-3-large"
    }

    response =
      Req.post!("https://api.openai.com/v1/embeddings",
        json: body,
        headers: headers
      )

    case response.status do
      200 ->
        response.body["data"]
        |> Enum.map(fn %{"embedding" => embedding} -> embedding end)
        |> then(&{:ok, &1})

      status ->
        {:error, response.body}
    end
  end
end
```

Opts can be used to make embedding models that are dynamic depending on the resource, i.e

```elixir
embedding_model {MyApp.OpenAiEmbeddingModel, model: "a-specific-model"}
```

Those opts are available in the `_opts` argument to functions on your embedding model


# Roadmap

- more action types, like:
  - bulk updates
  - bulk destroys
  - bulk creates.

# How to play with it

1. Setup `LangChain`
2. Modify a `LangChain` using `AshAi.setup_ash_ai/2` or use `AshAi.iex_chat` (see below)
2. Run `iex -S mix` and then run `AshAi.iex_chat` to start chatting with your app.
3. Build your own chat interface. See the implementation of `AshAi.iex_chat` to see how its done.

## Using AshAi.iex_chat

```elixir
defmodule MyApp.ChatBot do
  alias LangChain.Chains.LLMChain
  alias LangChain.ChatModels.ChatOpenAI

  def iex_chat(actor \\ nil) do
    %{
      llm: ChatOpenAI.new!(%{model: "gpt-4o", stream: true),
      verbose: true
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
