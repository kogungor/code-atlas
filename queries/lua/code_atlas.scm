(function_declaration
  name: (_) @function.name) @function.outer

(assignment_statement
  (variable_list
    (_) @function.name)
  (expression_list
    (function_definition))) @function.outer
