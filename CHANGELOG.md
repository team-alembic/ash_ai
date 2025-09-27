# Change Log

All notable changes to this project will be documented in this file.
See [Conventional Commits](Https://conventionalcommits.org) for commit guidelines.

<!-- changelog -->

## [v0.2.13](https://github.com/ash-project/ash_ai/compare/v0.2.12...v0.2.13) (2025-09-27)




### Bug Fixes:

* minor QOL improvement to the redirection to other pages (#120) by Abdessabour Moutik [(#120)](https://github.com/ash-project/ash_ai/pull/120)

* ash_ai.gen.chat to validate text presence in messages (#119) by Daniel Hoelzgen [(#119)](https://github.com/ash-project/ash_ai/pull/119)

* BadMapError when LangChain/MCP calls tools without arguments (#118) by [@matthewsinclair](https://github.com/matthewsinclair) [(#118)](https://github.com/ash-project/ash_ai/pull/118)

### Improvements:

* don't install usage rules as part of installing ash ai by [@zachdaniel](https://github.com/zachdaniel)

* Support LangChain 0.4 (#124) by Arjan Scherpenisse [(#124)](https://github.com/ash-project/ash_ai/pull/124)

## [v0.2.12](https://github.com/ash-project/ash_ai/compare/v0.2.11...v0.2.12) (2025-08-31)




### Bug Fixes:

* pass context option through setup_ash_ai to nested actions (#111) by [@bradleygolden](https://github.com/bradleygolden)

### Improvements:

* don't show input if no inputs to action by [@zachdaniel](https://github.com/zachdaniel)

* add `action_parameters` option by [@zachdaniel](https://github.com/zachdaniel)

## [v0.2.11](https://github.com/ash-project/ash_ai/compare/v0.2.10...v0.2.11) (2025-08-21)




### Bug Fixes:

* Respect resource pagination limits (#108) by kik4444

* eliminate chat_live compile warning (#107) by [@andyl](https://github.com/andyl)

* log the action name (#102) by [@barnabasJ](https://github.com/barnabasJ)

### Improvements:

* move permissions check of tools until after appropriate filtering (#104) by [@jgwmaxwell](https://github.com/jgwmaxwell)

* Add default adapter for ChatGoogleAI (#99) by [@mylanconnolly](https://github.com/mylanconnolly)

## [v0.2.10](https://github.com/ash-project/ash_ai/compare/v0.2.9...v0.2.10) (2025-08-07)




### Bug Fixes:

* log the action name (#102) by [@barnabasJ](https://github.com/barnabasJ)

### Improvements:

* move permissions check of tools until after appropriate filtering (#104) by [@jgwmaxwell](https://github.com/jgwmaxwell)

* Add default adapter for ChatGoogleAI (#99) by [@mylanconnolly](https://github.com/mylanconnolly)

## [v0.2.9](https://github.com/ash-project/ash_ai/compare/v0.2.8...v0.2.9) (2025-07-22)




### Improvements:

* mark all fields as required by [@zachdaniel](https://github.com/zachdaniel)

* handle number constraints by [@zachdaniel](https://github.com/zachdaniel)

* Add on_tool_start and on_tool_end callbacks (#96) by [@bradleygolden](https://github.com/bradleygolden)

## [v0.2.8](https://github.com/ash-project/ash_ai/compare/v0.2.7...v0.2.8) (2025-07-17)




### Improvements:

* add typed struct example to usage rules & docs by [@zachdaniel](https://github.com/zachdaniel)

## [v0.2.7](https://github.com/ash-project/ash_ai/compare/v0.2.6...v0.2.7) (2025-07-17)




### Bug Fixes:

* separate custom_context from llm initialization in ash_ai.gen.chat (#88) by [@germanbottosur](https://github.com/germanbottosur)

## [v0.2.6](https://github.com/ash-project/ash_ai/compare/v0.2.5...v0.2.6) (2025-07-05)




### Bug Fixes:

* handle missing user module more gracefully by [@zachdaniel](https://github.com/zachdaniel)

* properly install usage rules by [@zachdaniel](https://github.com/zachdaniel)

## [v0.2.5](https://github.com/ash-project/ash_ai/compare/v0.2.4...v0.2.5) (2025-07-03)




### Improvements:

* support sub rules in usage rules tools by [@zachdaniel](https://github.com/zachdaniel)

## [v0.2.4](https://github.com/ash-project/ash_ai/compare/v0.2.3...v0.2.4) (2025-07-02)




### Bug Fixes:

* allow for a custom json_processor (#80) by [@TwistingTwists](https://github.com/TwistingTwists)

* changed chat-live message history order before adding it to langchain (#78) by srmico

* crash with embedded resource (#77) by [@nallwhy](https://github.com/nallwhy)

### Improvements:

* add documentation for tool private attribute behavior (#81) by marot

* add documentation for tool private attribute behavior by marot

* install usage rules better by [@zachdaniel](https://github.com/zachdaniel)

## [v0.2.3](https://github.com/ash-project/ash_ai/compare/v0.2.2...v0.2.3) (2025-06-25)




### Bug Fixes:

* unsafe usage in mdex (#73) by [@TwistingTwists](https://github.com/TwistingTwists)

### Improvements:

* update usage rules w/ more prompt actions by [@zachdaniel](https://github.com/zachdaniel)

* multi-provider support prerequisite - eliminate open api spex reliance (#64) by KasparKipp

* Support various additional prompt formats (#72) by [@TwistingTwists](https://github.com/TwistingTwists)

## [v0.2.2](https://github.com/ash-project/ash_ai/compare/v0.2.1...v0.2.2) (2025-06-11)




### Bug Fixes:

* properly close connection after sending the endpoint by [@zachdaniel](https://github.com/zachdaniel)

### Improvements:

* use relative paths in usage rules MCP by [@zachdaniel](https://github.com/zachdaniel)

## [v0.2.1](https://github.com/ash-project/ash_ai/compare/v0.2.0...v0.2.1) (2025-06-11)




### Bug Fixes:

* fix installer waiting for input by [@zachdaniel](https://github.com/zachdaniel)

### Improvements:

* make usage rules display all and show file paths instead of by [@zachdaniel](https://github.com/zachdaniel)

## [v0.2.0](https://github.com/ash-project/ash_ai/compare/v0.1.11...v0.2.0) (2025-06-10)




### Features:

* Json Processor for providers that do not support json_schema or tool calling (#49) by [@TwistingTwists](https://github.com/TwistingTwists)

* improvement: Usage rules mcp integration (#60) by [Barnabas Jovanovics](https://https://github.com/barnabasJ)

### Bug Fixes:

* tasks: fix prompt typo (#62) by ChristianAlexander

* endpoint matching for url 'starting from' api.openai.com (#57) by [@TwistingTwists](https://github.com/TwistingTwists)

* fix oban option passing by [@zachdaniel](https://github.com/zachdaniel)

* require an explicit endpoint set by [@zachdaniel](https://github.com/zachdaniel)

* pass tenant to AshOban.run_trigger by [@zachdaniel](https://github.com/zachdaniel)

### Improvements:

* sync usage rules on project creation by [@zachdaniel](https://github.com/zachdaniel)

* more context in error messages (#56) by [@TwistingTwists](https://github.com/TwistingTwists)

* When using Adapter.CompletionTool (for anthropic) add the cache_control (#51) by Rodolfo Torres

* more realistic handling of example generation (#50) by [@TwistingTwists](https://github.com/TwistingTwists)

## [v0.1.11](https://github.com/ash-project/ash_ai/compare/v0.1.10...v0.1.11) (2025-06-04)




### Improvements:

* adapters for prompt-backed actions

* add completion tool adapter, infer it from anthropic

## [v0.1.10](https://github.com/ash-project/ash_ai/compare/v0.1.9...v0.1.10) (2025-05-30)




### Bug Fixes:

* use after_action instead of after_transaction to afford atomic_updates (#43)

## [v0.1.9](https://github.com/ash-project/ash_ai/compare/v0.1.8...v0.1.9) (2025-05-27)




### Bug Fixes:

* remove unnecessary source type from generated chat code

## [v0.1.8](https://github.com/ash-project/ash_ai/compare/v0.1.7...v0.1.8) (2025-05-27)




### Improvements:

* overhaul ash_ai.gen.chat to store tool calls

* make the dev mcp path configurable (#38)

## [v0.1.7](https://github.com/ash-project/ash_ai/compare/v0.1.6...v0.1.7) (2025-05-21)




### Improvements:

* Add usage rules for Ash AI

## [v0.1.6](https://github.com/ash-project/ash_ai/compare/v0.1.5...v0.1.6) (2025-05-21)

### Improvements:

* Rename package_ruels to usage_rules


## [v0.1.5](https://github.com/ash-project/ash_ai/compare/v0.1.4...v0.1.5) (2025-05-21)




### Bug Fixes:

* properly display generators, add new usage-rules.md dev tool

### Improvements:

* add `ash_ai.gen.package_rules` task to create a rules file

## [v0.1.4](https://github.com/ash-project/ash_ai/compare/v0.1.3...v0.1.4) (2025-05-20)




### Bug Fixes:

* Replace doc with description (#36)

## [v0.1.3](https://github.com/ash-project/ash_ai/compare/v0.1.2...v0.1.3) (2025-05-20)




### Bug Fixes:

* use `description` not `doc`

## [v0.1.2](https://github.com/ash-project/ash_ai/compare/v0.1.1...v0.1.2) (2025-05-20)




### Bug Fixes:

* improve chat ui heex template

* don't reply to the initialized notification (#35)

### Improvements:

* update chat heex template. (#33)

## [v0.1.1](https://github.com/ash-project/ash_ai/compare/v0.1.0...v0.1.1) (2025-05-14)




### Bug Fixes:

* more fixes for gen.chat message order

* properly generate chat message log

### Improvements:

* fix update pre_flight permission request for tools

## [v0.1.0](https://github.com/ash-project/ash_ai/compare/v0.1.0...v0.1.0) (2025-05-14)




### Bug Fixes:

* always configure chat queues

* Set additionalProperties to false in parameter_schema (#16)

* Fix load opt not working (#12)

* don't pass nil input in function/4 (#8)

* Fix schema type of actions of Options (#5)

* use `:asc` to put lowest distance records at the top

* use correct ops in vector before action

* use `message` instead of `reason`

### Improvements:

* add `mix ash_ai.gen.mcp`

* dev tools MCP

* remove vector search action

* Add an MCP server support

* support tool-level descriptions

* better name trigger

* use bulk actions for update/destroy

* first draft of `mix ash_ai.gen.chat` (#19)

* allow read actions to be aggregated in addition to run

* set up CI, various fixes and refactors

* Add aggregates to filter properties (#15)

* Add async opt to Tool

* Add load opt to tool (#9)

* Add tenant to opts of setup_ash_ai/2 (#4)

* add installer

* add tenants to action calls in functions

* add `:manual` strategy

* allow specifying tools by name of tool

* strict modes & other various improvements

* make embedding model parameterizable

* remove unnecessary deps, use langchain

* make embedding models for arbitrary vectorization

* use configured name for tools

* make the DSL more `tool` centric

* add vectorize section
