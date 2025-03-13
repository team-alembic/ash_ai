defmodule AshAi.Info do
  use Spark.InfoGenerator, extension: AshAi, sections: [:agents, :vectorize]

  def exposes?(domain, resource, action) do
    Enum.any?(agents(domain), fn %{resource: exposed_resource, actions: actions} ->
      exposed_resource == resource and action in actions
    end)
  end
end
