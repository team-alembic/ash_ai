defmodule AshAi.DevTools do
  @moduledoc false
  use Ash.Domain,
    extensions: [AshAi],
    validate_config_inclusion?: false

  tools do
    tool :list_ash_resources, AshAi.DevTools.Tools, :list_ash_resources do
      description "List all Ash resources in the app along with their domains"
    end

    # tool :get_package_rules, AshAi.DevTools.Tools, :get_package_rules do
    #   description """
    #   Get package rules for the provided packags.
    #   Do this early as soon as you see that you are working with a given package.
    #   """
    # end

    tool :list_generators, AshAi.DevTools.Tools, :list_generators do
      description "List available generators and their documentation"
    end
  end

  resources do
    resource AshAi.DevTools.Tools
  end
end
