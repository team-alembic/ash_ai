defmodule AshAi.Validations.ActorIsAshAi do
  use Ash.Resource.Validation

  def describe(_), do: "actor is %AshAi{}"

  def validate(_, _, %{actor: %AshAi{}}) do
    :ok
  end

  def validate(_, _, _) do
    {:error, "actor must be Ash AI"}
  end

  def atomic(changeset, opts, context) do
    validate(changeset, opts, context)
  end
end
