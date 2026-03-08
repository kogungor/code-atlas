(function_declaration
  name: (identifier) @function.name) @function.outer

(method_definition
  name: (property_identifier) @function.name) @function.outer

(lexical_declaration
  (variable_declarator
    name: (identifier) @function.name
    value: [(arrow_function) (function)])) @function.outer
