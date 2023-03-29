[
  (parenthesized_expression)
  (generator_expression)
  (list_comprehension)
  (set_comprehension)
  (dictionary_comprehension)

  (tuple_pattern)
  (list_pattern)
  (binary_operator)

  (lambda)

  (concatenated_string)
] @indent.begin

((list) @indent.align
 (#set! indent.open_delimiter "[")
 (#set! indent.close_delimiter "]")
 (#set! indent.dedent_hanging_close 1)
)
((dictionary) @indent.align
 (#set! indent.open_delimiter "{")
 (#set! indent.close_delimiter "}")
 (#set! indent.dedent_hanging_close 1)
)
((set) @indent.align
 (#set! indent.open_delimiter "{")
 (#set! indent.close_delimiter "}")
 (#set! indent.dedent_hanging_close 1)
)

((match_statement) @indent.begin)
((case_clause) @indent.begin)
((for_statement) @indent.begin)
((if_statement) @indent.begin)
((while_statement) @indent.begin)
((try_statement) @indent.begin)
(ERROR "try" ":" @indent.begin)
((function_definition) @indent.begin)
((class_definition) @indent.begin)
((with_statement) @indent.begin)
((match_statement) @indent.begin)
((case_clause) @indent.begin)

(if_statement
  condition: (parenthesized_expression) @indent.align
  (#set! indent.open_delimiter "(")
  (#set! indent.close_delimiter ")")
  (#set! indent.avoid_last_matching_next 1)
)
(while_statement
  condition: (parenthesized_expression) @indent.align
  (#set! indent.open_delimiter "(")
  (#set! indent.close_delimiter ")")
  (#set! indent.avoid_last_matching_next 1)
)

(ERROR "(" @indent.align (#set! indent.open_delimiter "(") (#set! indent.close_delimiter ")") . (_)) 
((argument_list) @indent.align
 (#set! indent.open_delimiter "(")
 (#set! indent.close_delimiter ")")
 (#set! indent.dedent_hanging_close 1))
((parameters) @indent.align
 (#set! indent.open_delimiter "(")
 (#set! indent.close_delimiter ")")
 (#set! indent.avoid_last_matching_next 1))
((tuple) @indent.align
 (#set! indent.open_delimiter "(")
 (#set! indent.close_delimiter ")")
 (#set! indent.dedent_hanging_close 1))
((import_from_statement "(" _ ")") @indent.align 
 (#set! indent.open_delimiter "(")
 (#set! indent.close_delimiter ")")
 (#set! indent.dedent_hanging_close 1))

(ERROR "[" @indent.align (#set! indent.open_delimiter "[") (#set! indent.close_delimiter "]") . (_)) 

(ERROR "{" @indent.align (#set! indent.open_delimiter "{") (#set! indent.close_delimiter "}") . (_)) 

(parenthesized_expression ")" @indent.end)
(generator_expression ")" @indent.end)
(list_comprehension "]" @indent.end)
(set_comprehension "}" @indent.end)
(dictionary_comprehension "}" @indent.end)

(tuple_pattern ")" @indent.end)
(list_pattern "]" @indent.end)

((return_statement) @indent.dedent
 (#set! indent.body 0)
 (#set! indent.end 0)
 (#set! indent.after 1))
((raise_statement) @indent.dedent
 (#set! indent.body 0)
 (#set! indent.end 0)
 (#set! indent.after 1))
((break_statement) @indent.dedent
 (#set! indent.body 0)
 (#set! indent.end 0)
 (#set! indent.after 1))
((continue_statement) @indent.dedent
 (#set! indent.body 0)
 (#set! indent.end 0)
 (#set! indent.after 1))

(
 (except_clause
  "except" @indent.branch
  (_) )
)

(
 (finally_clause
  "finally" @indent.branch
  (_) )
)

(elif_clause
  "elif" @indent.branch
  consequence: (_) )

(else_clause
 "else" @indent.branch 
 body: (_) )

(string) @indent.auto

