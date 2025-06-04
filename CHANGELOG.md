# Change Log

All notable changes to this project will be documented in this file.
See [Conventional Commits](Https://conventionalcommits.org) for commit guidelines.

<!-- changelog -->

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
