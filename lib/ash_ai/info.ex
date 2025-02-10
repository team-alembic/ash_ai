defmodule AshAi.Info do
  use Spark.InfoGenerator, extension: AshAi, sections: [:ai_agent, :vectorize]
end
