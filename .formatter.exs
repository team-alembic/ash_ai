spark_locals_without_parens = [
  attributes: 1,
  name: 1,
  strategy: 1,
  text: 1,
  tool: 3,
  tool: 4,
  used_attributes: 1
]

[
  export: [
    locals_without_parens: spark_locals_without_parens
  ],
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"]
]
