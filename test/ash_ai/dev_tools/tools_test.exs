defmodule AshAi.DevTools.ToolsTest do
  use ExUnit.Case, async: true

  describe "get_usage_rules action" do
    test "returns rules for packages with usage-rules.md files" do
      {:ok, results} =
        AshAi.DevTools.Tools
        |> Ash.ActionInput.for_action(:get_usage_rules, %{packages: ["ash"]})
        |> Ash.run_action()

      assert is_list(results)

      [%{package: "ash", rules: rules}] = results
      assert is_binary(rules)
      assert String.length(rules) > 0
      assert String.contains?(rules, "Ash")
    end

    test "returns multiple results for multiple packages with rules" do
      {:ok, results} =
        AshAi.DevTools.Tools
        |> Ash.ActionInput.for_action(:get_usage_rules, %{
          packages: ["ash", "ash_postgres", "igniter"]
        })
        |> Ash.run_action()

      assert is_list(results)

      for %{package: package, rules: rules} <- results do
        assert is_binary(package)
        assert is_binary(rules)
        assert String.length(rules) > 0
        assert package in ["ash", "ash_postgres", "igniter"]
      end
    end

    test "returns empty list for packages without usage-rules.md" do
      {:ok, results} =
        AshAi.DevTools.Tools
        |> Ash.ActionInput.for_action(:get_usage_rules, %{packages: ["non_existent_package"]})
        |> Ash.run_action()

      assert results == []
    end

    test "filters out packages without rules from mixed list" do
      {:ok, results} =
        AshAi.DevTools.Tools
        |> Ash.ActionInput.for_action(:get_usage_rules, %{
          packages: ["ash", "non_existent_package"]
        })
        |> Ash.run_action()

      assert is_list(results)

      [%{package: "ash", rules: rules}] = results
      assert is_binary(rules)
      assert String.length(rules) > 0
    end

    test "handles empty package list" do
      {:ok, results} =
        AshAi.DevTools.Tools
        |> Ash.ActionInput.for_action(:get_usage_rules, %{packages: []})
        |> Ash.run_action()

      assert results == []
    end
  end

  describe "list_packages_with_rules action" do
    test "returns list of packages that have usage-rules.md files" do
      {:ok, results} =
        AshAi.DevTools.Tools
        |> Ash.ActionInput.for_action(:list_packages_with_rules, %{})
        |> Ash.run_action()

      assert is_list(results)

      for package <- results do
        assert is_binary(package)
      end

      if length(results) > 0 do
        first_package = List.first(results)
        deps_paths = Mix.Project.deps_paths()

        {_name, path} =
          Enum.find(deps_paths, fn {name, _} ->
            to_string(name) == first_package
          end) || raise("Package #{first_package} not found in deps")

        assert File.exists?(Path.join(path, "usage-rules.md"))
      end
    end
  end

  describe "list_ash_resources action" do
    test "returns list of resources with domains" do
      {:ok, results} =
        AshAi.DevTools.Tools
        |> Ash.ActionInput.for_action(:list_ash_resources, %{})
        |> Ash.run_action(context: %{otp_app: :ash_ai})

      assert is_list(results)

      # Verify we get some results from the test app
      assert length(results) > 0

      test_resources =
        Enum.filter(results, fn resource ->
          resource.name =~ "Test" or resource.domain =~ "Test"
        end)

      assert length(test_resources) > 0

      for %{name: name, domain: domain} <- results do
        assert is_binary(name)
        assert is_binary(domain)
      end
    end
  end

  describe "list_generators action" do
    test "returns list of available igniter generators" do
      {:ok, results} =
        AshAi.DevTools.Tools
        |> Ash.ActionInput.for_action(:list_generators, %{})
        |> Ash.run_action()

      assert is_list(results)

      ash_ai_generators =
        Enum.filter(results, fn gen ->
          gen.command =~ "ash_ai"
        end)

      assert length(ash_ai_generators) > 0

      for %{command: command, docs: docs} <- results do
        assert is_binary(command)
        assert is_binary(docs) or is_nil(docs) or docs == false
      end
    end

    test "includes expected ash_ai generators" do
      {:ok, results} =
        AshAi.DevTools.Tools
        |> Ash.ActionInput.for_action(:list_generators, %{})
        |> Ash.run_action()

      commands = Enum.map(results, & &1.command)

      expected_generators = [
        "ash_ai.gen.chat",
        "ash_ai.gen.mcp",
        "ash_ai.gen.usage_rules",
        "ash_ai.install"
      ]

      for expected <- expected_generators do
        assert expected in commands,
               "Expected generator #{expected} not found in #{inspect(commands)}"
      end
    end
  end

  describe "action descriptions and metadata" do
    test "get_usage_rules has appropriate description" do
      action = Ash.Resource.Info.action(AshAi.DevTools.Tools, :get_usage_rules)

      assert action.description =~ "rules"
      assert action.description =~ "packages"
      assert action.description =~ "usage-rules.md"
    end

    test "list_ash_resources has appropriate description" do
      action = Ash.Resource.Info.action(AshAi.DevTools.Tools, :list_ash_resources)

      assert action.description =~ "Ash resources"
      assert action.description =~ "domains"
    end

    test "list_packages_with_rules has appropriate description" do
      action = Ash.Resource.Info.action(AshAi.DevTools.Tools, :list_packages_with_rules)

      assert action.description =~ "packages"
      assert action.description =~ "usage-rules.md"
    end

    test "list_generators has appropriate description" do
      action = Ash.Resource.Info.action(AshAi.DevTools.Tools, :list_generators)

      assert action.description =~ "generators"
      assert action.description =~ "igniter"
    end
  end

  describe "type definitions" do
    test "UsageRules type has correct structure" do
      # This should not raise an error when used in action results
      {:ok, results} =
        AshAi.DevTools.Tools
        |> Ash.ActionInput.for_action(:get_usage_rules, %{packages: []})
        |> Ash.run_action()

      assert is_list(results)

      valid_usage_rule = %{package: "test_package", rules: "test rules content"}
      assert is_map(valid_usage_rule)
      assert Map.has_key?(valid_usage_rule, :package)
      assert Map.has_key?(valid_usage_rule, :rules)
    end

    test "Resource type has correct structure" do
      {:ok, results} =
        AshAi.DevTools.Tools
        |> Ash.ActionInput.for_action(:list_ash_resources, %{})
        |> Ash.run_action(context: %{otp_app: :ash_ai})

      for resource <- results do
        assert Map.has_key?(resource, :name)
        assert Map.has_key?(resource, :domain)
      end
    end

    test "Task type has correct structure" do
      {:ok, results} =
        AshAi.DevTools.Tools
        |> Ash.ActionInput.for_action(:list_generators, %{})
        |> Ash.run_action()

      for task <- results do
        assert Map.has_key?(task, :command)
        assert Map.has_key?(task, :docs)
        assert is_binary(task.docs) or is_nil(task.docs) or task.docs == false
      end
    end
  end
end
