module.exports = grammar({
  name: 'nova',

  extras: $ => [
    /\s/,
    $.comment,
  ],

  rules: {
    source_file: $ => repeat($._top_level),

    _top_level: $ => choice(
      $.function_declaration,
      $.type_declaration,
      $.trait_declaration,
      $.impl_declaration,
      $.import_declaration
    ),

    comment: $ => token(seq('#', /.*/)),

    // Import
    import_declaration: $ => seq(
      'import',
      field('module', $.scoped_identifier),
      optional(seq('as', field('alias', $.identifier))),
      optional(seq('{', commaSep($.identifier), '}'))
    ),

    // Trait & Impl
    trait_declaration: $ => seq(
      optional('pub'),
      'trait',
      field('name', $.identifier),
      ':',
      repeat($.function_declaration)
    ),

    impl_declaration: $ => seq(
      'impl',
      field('trait', $.identifier),
      'for',
      field('type', $.type_expression),
      ':',
      repeat($.function_declaration)
    ),

    // Function Declaration
    function_declaration: $ => seq(
      optional('pub'),
      'fn',
      field('name', $.identifier),
      field('parameters', $.parameter_list),
      optional(seq('->', field('return_type', $.type_expression))),
      optional(seq('where', field('contract', $._expression))),
      optional(seq(':', field('body', $.block)))
    ),

    parameter_list: $ => seq(
      '(',
      commaSep($.parameter),
      ')'
    ),

    parameter: $ => seq(
      optional('mut'),
      optional($.capability),
      field('name', $.identifier),
      ':',
      field('type', $.type_expression)
    ),

    capability: $ => choice('iso', 'val', 'ref', 'cap'),

    // Type Declaration
    type_declaration: $ => seq(
      optional('pub'),
      'type',
      field('name', $.identifier),
      '=',
      choice($.struct_definition, $.enum_definition, $.type_expression)
    ),

    struct_definition: $ => seq(
      'struct',
      ':',
      repeat1($.struct_field)
    ),

    struct_field: $ => seq(
      field('name', $.identifier),
      ':',
      field('type', $.type_expression)
    ),

    enum_definition: $ => seq(
      'enum',
      ':',
      repeat1($.enum_variant)
    ),

    enum_variant: $ => seq(
      field('name', $.identifier),
      optional(seq('(', commaSep($.type_expression), ')'))
    ),

    type_expression: $ => choice(
      $.identifier,
      seq('*mut', $.type_expression),
      seq('*const', $.type_expression),
      seq('[', $.type_expression, ']'),
      seq($.identifier, '[', commaSep($.type_expression), ']')
    ),

    // Statements
    block: $ => repeat1($._statement),

    _statement: $ => choice(
      $.let_statement,
      $.return_statement,
      $.if_statement,
      $.while_statement,
      $.for_statement,
      $.unsafe_statement,
      $.asm_statement,
      $.expression_statement
    ),

    let_statement: $ => seq(
      'let',
      optional('mut'),
      field('pattern', $._pattern),
      optional(seq(':', field('type', $.type_expression))),
      '=',
      field('value', $._expression)
    ),

    return_statement: $ => seq(
      'return',
      optional($._expression)
    ),

    if_statement: $ => seq(
      'if',
      field('condition', $._expression),
      ':',
      field('consequence', $.block),
      optional(seq('else', ':', field('alternative', $.block)))
    ),

    while_statement: $ => seq(
      'while',
      field('condition', $._expression),
      ':',
      field('body', $.block)
    ),

    for_statement: $ => seq(
      'for',
      field('pattern', $._pattern),
      'in',
      field('iterator', $._expression),
      ':',
      field('body', $.block)
    ),

    unsafe_statement: $ => seq(
      'unsafe',
      '(',
      $.identifier,
      ')',
      ':',
      field('body', $.block)
    ),

    asm_statement: $ => seq(
      'asm',
      '(',
      $.string_literal,
      ')'
    ),

    expression_statement: $ => $._expression,

    // Patterns
    _pattern: $ => choice(
      $.identifier,
      $.wildcard,
      $.literal
    ),

    wildcard: $ => '_',

    // Expressions
    _expression: $ => choice(
      $.identifier,
      $.literal,
      $.binary_expression,
      $.unary_expression,
      $.call_expression,
      $.field_expression
    ),

    binary_expression: $ => prec.left(1, seq(
      field('left', $._expression),
      field('operator', choice('+', '-', '*', '/', '%', '==', '!=', '<', '<=', '>', '>=', 'and', 'or', '&', '|', '^', '<<', '>>')),
      field('right', $._expression)
    )),

    unary_expression: $ => prec(2, seq(
      choice('-', '!', '~', '*', '&'),
      $._expression
    )),

    call_expression: $ => prec(3, seq(
      field('function', $._expression),
      field('arguments', seq('(', commaSep($._expression), ')'))
    )),

    field_expression: $ => prec(4, seq(
      field('argument', $._expression),
      '.',
      field('field', $.identifier)
    )),

    literal: $ => choice(
      $.integer_literal,
      $.float_literal,
      $.string_literal,
      $.boolean_literal
    ),

    integer_literal: $ => /\d+/,
    float_literal: $ => /\d+\.\d+/,
    string_literal: $ => /"(\\.|[^"\\])*"/,
    boolean_literal: $ => choice('true', 'false'),

    identifier: $ => /[a-zA-Z_][a-zA-Z0-9_]*/,
    scoped_identifier: $ => sep1($.identifier, '.')
  }
});

function commaSep(rule) {
  return optional(commaSep1(rule));
}

function commaSep1(rule) {
  return seq(rule, repeat(seq(',', rule)));
}

function sep1(rule, separator) {
  return seq(rule, repeat(seq(separator, rule)));
}
