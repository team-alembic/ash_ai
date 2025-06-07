defmodule AshAi.DevTools.Tools do
  @moduledoc false
  use Ash.Resource, domain: AshAi.DevTools

  defmodule Task do
    @moduledoc false
    use Ash.Type.NewType,
      subtype_of: :map,
      constraints: [
        fields: [
          command: [type: :string, allow_nil?: false, description: "The command to run"],
          docs: [type: :string, allow_nil?: false, description: "The documentation for the task"]
        ]
      ]
  end

  defmodule Resource do
    @moduledoc false
    use Ash.Type.NewType,
      subtype_of: :map,
      constraints: [
        fields: [
          name: [type: :string, allow_nil?: false, description: "The name of the resource module"],
          domain: [
            type: :string,
            allow_nil?: false,
            description: "The name of the resource's domain module"
          ]
        ]
      ]
  end

  defmodule UsageRules do
    @moduledoc false
    use Ash.Type.NewType,
      subtype_of: :map,
      constraints: [
        fields: [
          package: [type: :string, allow_nil?: false, description: "The name of the package"],
          rules: [
            type: :string,
            allow_nil?: false,
            description: "The contents of the package's rules file"
          ]
        ]
      ]
  end

  actions do
    action :list_ash_resources, {:array, Resource} do
      description """
      Lists Ash resources and their domains.
      """

      run fn input, _ ->
        Ash.Info.domains_and_resources(input.context.otp_app)
        |> Enum.flat_map(fn {domain, resources} ->
          Enum.map(resources, fn resource ->
            %{domain: inspect(domain), name: inspect(resource)}
          end)
        end)
        |> then(&{:ok, &1})
      end
    end

    action :get_usage_rules, {:array, UsageRules} do
      description """
      Lists the usage rules for the provided packages.
      Use this to discover how packages are intended to be used.
      Not all packages have rules, but when they do they are stored in a `usage-rules.md` file.
      """

      argument :packages, {:array, :string} do
        allow_nil? false
        description "The packages to get usage rules for"
      end

      run fn input, _ ->
        Mix.Project.deps_paths()
        |> Enum.filter(fn {name, _path} ->
          to_string(name) in input.arguments.packages
        end)
        |> Enum.flat_map(fn {name, path} ->
          path
          |> Path.join("usage-rules.md")
          |> File.exists?()
          |> case do
            true ->
              [
                %{
                  package: to_string(name),
                  rules: File.read!(Path.join(path, "usage-rules.md"))
                }
              ]

            false ->
              []
          end
        end)
        |> then(&{:ok, &1})
      end
    end

    action :list_packages_with_rules, {:array, :string} do
      description """
      Lists all packages in this project that have usage-rules.md files.
      Use this to discover which packages provide usage guidance.
      """

      run fn _input, _ ->
        Mix.Project.deps_paths()
        |> Enum.filter(fn {_name, path} ->
          Path.join(path, "usage-rules.md") |> File.exists?()
        end)
        |> Enum.map(fn {name, _path} -> to_string(name) end)
        |> then(&{:ok, &1})
      end
    end

    action :list_generators, {:array, Task} do
      description """
      Lists available igniter generators. Run with `mix <task_name>`. Pass `--dry-run` to see what the effects will be. Always pass `--yes` when running to accept changes automatically
      """

      run fn input, _ ->
        Mix.Task.load_all()
        |> Enum.filter(fn module ->
          Code.ensure_loaded?(module) && function_exported?(module, :igniter, 1)
        end)
        |> Enum.map(fn module ->
          %{docs: Mix.Task.moduledoc(module), command: Mix.Task.task_name(module)}
        end)
        |> then(&{:ok, &1})
      end
    end
  end
end
