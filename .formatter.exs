spark_locals_without_parens = [
  attributes: 1,
  embedding_model: 1,
  name: 1,
  strategy: 1,
  text: 1,
  tool: 3,
  tool: 4,
  used_attributes: 1,
  define_update_action_for_manual_strategy?: 1
]

[
  export: [
    locals_without_parens: spark_locals_without_parens
  ],
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"]
]
