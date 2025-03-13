defmodule AshAi.Info do
  use Spark.InfoGenerator, extension: AshAi, sections: [:tools, :vectorize]
end
