# Change Log

All notable changes to this project will be documented in this file.
See [Conventional Commits](Https://conventionalcommits.org) for commit guidelines.

<!-- changelog -->

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
