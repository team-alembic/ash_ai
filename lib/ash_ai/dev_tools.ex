defmodule AshAi.DevTools do
  @moduledoc false
  use Ash.Domain,
    extensions: [AshAi],
    validate_config_inclusion?: false

  tools do
    tool :list_ash_resources, AshAi.DevTools.Tools, :list_ash_resources
    tool :list_generators, AshAi.DevTools.Tools, :list_generators
  end

  resources do
    resource AshAi.DevTools.Tools
  end
end
