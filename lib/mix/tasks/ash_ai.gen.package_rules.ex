defmodule Mix.Tasks.AshAi.Gen.PackageRules.Docs do
  @moduledoc false

  @spec short_doc() :: String.t()
  def short_doc do
    "Combine the package rules for the provided packages into the provided file."
  end

  @spec example() :: String.t()
  def example do
    "mix ash_ai.gen.package_rules rules.md ash ash_postgres phoenix"
  end

  @spec long_doc() :: String.t()
  def long_doc do
    """
    #{short_doc()}

    ## Example

    ```sh
    #{example()}
    ```
    """
  end
end

if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.AshAi.Gen.PackageRules do
    @shortdoc "#{__MODULE__.Docs.short_doc()}"

    @moduledoc __MODULE__.Docs.long_doc()

    use Igniter.Mix.Task

    @impl Igniter.Mix.Task
    def info(_argv, _composing_task) do
      %Igniter.Mix.Task.Info{
        # Groups allow for overlapping arguments for tasks by the same author
        # See the generators guide for more.
        group: :ash_ai,
        example: __MODULE__.Docs.example(),
        positional: [
          :file,
          packages: [rest: true]
        ]
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      contents =
        Mix.Project.deps_paths()
        |> Enum.filter(fn {name, _path} ->
          to_string(name) in igniter.args.positional.packages
        end)
        |> Enum.map_join("\n", fn {name, path} ->
          path
          |> Path.join("usage-rules.md")
          |> File.exists?()
          |> case do
            true ->
              "## #{name} usage\n" <>
                File.read!(Path.join(path, "usage-rules.md"))

            false ->
              []
          end
        end)
        |> then(fn contents ->
          "<-- package-rules-start -->\n" <> contents <> "<-- package-rules-end -->\n"
        end)

      Igniter.create_or_update_file(
        igniter,
        igniter.args.positional.file,
        contents,
        fn source ->
          current_file = Rewrite.Source.get(source, :content)

          new_content =
            case String.split(current_file, [
                   "<-- package-rules-start -->",
                   "<-- package-rules-end -->"
                 ]) do
              [prelude, _, postlude] ->
                prelude <> contents <> postlude

              [prelude] ->
                prelude <> contents
            end

          Rewrite.Source.update(source, :content, new_content)
        end
      )
    end
  end
else
  defmodule Mix.Tasks.AshAi.Gen.PackageRules do
    @shortdoc "#{__MODULE__.Docs.short_doc()} | Install `igniter` to use"

    @moduledoc __MODULE__.Docs.long_doc()

    use Mix.Task

    @impl Mix.Task
    def run(_argv) do
      Mix.shell().error("""
      The task 'ash_ai.gen.package_rules' requires igniter. Please install igniter and try again.

      For more information, see: https://hexdocs.pm/igniter/readme.html#installation
      """)

      exit({:shutdown, 1})
    end
  end
end
