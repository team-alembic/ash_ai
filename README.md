# AshAi

This is a _HIGHLY EXPERIMENTAL_ package. It is 500 lines of code built for a demo.

## What is it?

This is a chat interface for your Ash app. It can call actions on your resources
to fulfill requests. It will always honor your policy rules on your application, and
an actor can be provided, whereby all actions will be taken on their behalf.

The bot may very well do things you "don't want it to do", but it cannot perform
any kind of privelege escalation because it always operates by calling actions on
resources, never by accessing data directly.

## LangChain

I'm experimenting with Langchain being the basis for this package. Try it out yourself with something like this. 

```elixir
defmodule MyApp.ChatBot do
  alias LangChain.Chains.LLMChain
  alias LangChain.ChatModels.ChatOpenAI
  alias LangChain.Message

  def iex_chat(actor \\ nil) do
    %{
      llm: ChatOpenAI.new!(%{model: "gpt-4o", stream: true),
      verbose?: true
    }
    |> LLMChain.new!()
    |> AshAi.iex_chat(actor: actor, otp_app: :my_app)
  end
end

# and expose actions in your domains


agents do
  expose_resource MyApp.MyDomain.MyResource, [:list, :of, :actions]
  expose_resource MyApp.MyDomain.MyResource2, [:list, :of, :actions]
end

```

## Current status:

Experimenting with adding vectorized fields and trying to get agents to use them.
The filter schema is quite complex and the gpt4o doesn't seem to be able to
figure out how to use them (i.e provide input and a predicate like `eq`).
It may not be the best approach compared to advising users to add search
actions that use vectors and foregoing the complex filter schema.

## What goes into making this ready?

1. Must be made agnostic to provider.
   Right now it works directly with Open AI, using an environment variable.
2. Some easier ways to do the chat on a loop where the interface is something like a chat window
   in liveview. Streaming responses to callers.
3. Some kind of management of how much of the context window we are using. Trim chat history to keep
   context window small.
4. Customization of the initial system prompt.
5. At _least_ one test should be written :D

## What else ought to happen?

1. more action types, like bulk updates, bulk destroys, bulk creates.

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

1. Set the environment variable `OPENAI_API_KEY` to your Open AI API key.
2. Run `iex -S mix` and then run `AshAi.iex_chat` to start chatting with your app.
3. To build your own chat interface, you'll use `AshAi.instruct/2`. See the implementation
   of `AshAi.iex_chat` to see how its done.

### Example

```elixir
AshAi.iex_chat(actor: user, actions: [{Twitter.Tweets.Tweet, :*}])
```
