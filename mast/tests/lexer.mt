def [=> makeMonteLexer] := ::"import".script("lib/monte/monte_lexer")

def lex(s):
    def l := makeMonteLexer(s, "test")
    def toks := [for [tag, data, _ ] in (l) [tag, data]]
    if ((def err := l.getSyntaxError()) != null):
        throw(err)
    if (toks.size() > 0 && toks.last()[0] == "EOL"):
       return toks.slice(0, toks.size() - 1)
    return toks

def test_ident(assert):
    assert.equal(lex("foo_bar9"), [["IDENTIFIER", "foo_bar9"]])
    assert.equal(lex("foo"), [["IDENTIFIER", "foo"]])

def test_char(assert):
    assert.equal(lex("'z'"), [[".char.", 'z']])
    assert.equal(lex("'\\n'"), [[".char.", '\n']])
    assert.equal(lex("'\\u0061'"), [[".char.", 'a']])
    assert.equal(lex("'\\x61'"), [[".char.", 'a']])

def test_string(assert):
    assert.equal(lex(`"foo\$\nbar"`), [[".String.", "foobar"]])
    assert.equal(lex(`"foo"`),        [[".String.", "foo"]])
    assert.equal(lex(`"foo bar 9"`),  [[".String.", "foo bar 9"]])
    assert.equal(lex(`"foo\nbar"`),  [[".String.", "foo\nbar"]])

def test_integer(assert):
    assert.equal(lex("0"), [[".int.", 0]])
    assert.equal(lex("7"), [[".int.", 7]])
    assert.equal(lex("3_000"), [[".int.", 3000]])
    assert.equal(lex("0xABad1dea"), [[".int.", 2880249322]])

def test_float(assert):
    assert.equal(lex("1e9"), [[".float64.", 1e9]])
    assert.equal(lex("3.1415E17"), [[".float64.", 3.1415E17]])
    assert.equal(lex("0.91"), [[".float64.", 0.91]])
    assert.equal(lex("3e-2"), [[".float64.", 3e-2]])

def test_holes(assert):
    assert.equal(lex("${"), [["${", null]])
    assert.equal(lex("$blee"), [["DOLLAR_IDENT", "blee"]])
    assert.equal(lex("@{"), [["@{", null]])
    assert.equal(lex("@blee"), [["AT_IDENT", "blee"]])
    assert.equal(lex("@_fred"), [["AT_IDENT", "_fred"]])
    assert.equal(lex("@_"), [["AT_IDENT", "_"]])

def test_braces(assert):
    assert.equal(lex("[a, 1]"),
                 [["[", null],
                  ["IDENTIFIER", "a"],
                  [",", null],
                  [".int.", 1],
                  ["]", null]])
    assert.equal(lex("{1}"),
                 [["{", null],
                  [".int.", 1],
                  ["}", null]])
    assert.equal(lex("(a)"),
                 [["(", null],
                  ["IDENTIFIER", "a"],
                  [")", null]])

def test_dot(assert):
    assert.equal(lex("."), [[".", null]])
    assert.equal(lex(".."), [["..", null]])
    assert.equal(lex("..!"), [["..!", null]])

def test_caret(assert):
    assert.equal(lex("^"), [["^", null]])
    assert.equal(lex("^="), [["^=", null]])

def test_plus(assert):
    assert.equal(lex("+"), [["+", null]])
    assert.equal(lex("+="), [["+=", null]])

def test_minus(assert):
    assert.equal(lex("-"), [["-", null]])
    assert.equal(lex("-="), [["-=", null]])
    assert.equal(lex("-> {"), [["->", null], ["{", null]])

def test_colon(assert):
    assert.equal(lex(":x"), [[":", null], ["IDENTIFIER", "x"]])
    assert.equal(lex(":="), [[":=", null]])
    assert.equal(lex("::"), [["::", null]])

def test_crunch(assert):
    assert.equal(lex("<"), [["<", null]])
    assert.equal(lex("<-"), [["<-", null]])
    assert.equal(lex("<="), [["<=", null]])
    assert.equal(lex("<<="), [["<<=", null]])
    assert.equal(lex("<=>"), [["<=>", null]])

def test_zap(assert):
    assert.equal(lex(">"), [[">", null]])
    assert.equal(lex(">="), [[">=", null]])
    assert.equal(lex(">>="), [[">>=", null]])

def test_star(assert):
    assert.equal(lex("*"), [["*", null]])
    assert.equal(lex("*="), [["*=", null]])
    assert.equal(lex("**"), [["**", null]])
    assert.equal(lex("**="), [["**=", null]])

def test_slash(assert):
    assert.equal(lex("/"), [["/", null]])
    assert.equal(lex("/="), [["/=", null]])
    assert.equal(lex("//"), [["//", null]])
    assert.equal(lex("//="), [["//=", null]])

def test_mod(assert):
    assert.equal(lex("%"), [["%", null]])
    assert.equal(lex("%="), [["%=", null]])

def test_comment(assert):
    assert.equal(lex("# yes\n1"), [["#", " yes"], ["EOL", null],
                                   [".int.", 1]])

def test_bang(assert):
    assert.equal(lex("!"), [["!", null]])
    assert.equal(lex("!="), [["!=", null]])
    assert.equal(lex("!~"), [["!~", null]])

def test_eq(assert):
    assert.equal(lex("=="), [["==", null]])
    assert.equal(lex("=~"), [["=~", null]])
    assert.equal(lex("=>"), [["=>", null]])

def test_and(assert):
    assert.equal(lex("&"), [["&", null]])
    assert.equal(lex("&="), [["&=", null]])
    assert.equal(lex("&!"), [["&!", null]])
    assert.equal(lex("&&"), [["&&", null]])

def test_or(assert):
    assert.equal(lex("|"), [["|", null]])
    assert.equal(lex("|="), [["|=", null]])


def SIMPLE_INDENT := "
foo:
  baz


"

def ARROW_INDENT := "
foo ->
  baz


"

def SIMPLE_DEDENT := "
foo:
  baz
blee
"

def VERTICAL_SPACE := "
foo:

  baz


blee
"

def HORIZ_SPACE := "
foo:    
  baz
blee
"

def MULTI_INDENT := "
foo:
  baz:
     biz
blee
"

def UNBALANCED := "
foo:
  baz:
     biz
 blee
"

def UNBALANCED2 := "
foo:
  baz
   blee
"

def PARENS := "
(foo,
 baz:
  blee
 )
"

#TODO decide whether to follow python's "no indent tokens inside
#parens" strategy or have ways to jump in/out of indentation-awareness
def CONTINUATION := "
foo (
  baz
    biz
 )
blee
"
def test_indent_simple(assert):
    assert.equal(
        lex(SIMPLE_INDENT),
        [["EOL", null], ["IDENTIFIER", "foo"], [":", null], ["EOL", null],
         ["INDENT", null], ["IDENTIFIER", "baz"], ["DEDENT", null],
         ["EOL", null], ["EOL", null]])

def test_indent_arrow(assert):
    assert.equal(
        lex(ARROW_INDENT),
        [["EOL", null], ["IDENTIFIER", "foo"], ["->", null], ["EOL", null],
         ["INDENT", null], ["IDENTIFIER", "baz"], ["DEDENT", null],
         ["EOL", null], ["EOL", null]])

def test_indent_dedent(assert):
    assert.equal(
        lex(SIMPLE_DEDENT),
        [["EOL", null], ["IDENTIFIER", "foo"], [":", null], ["EOL", null],
         ["INDENT", null], ["IDENTIFIER", "baz"], ["DEDENT", null],
         ["EOL", null], ["IDENTIFIER", "blee"]])

def test_indent_vertical(assert):
    assert.equal(
        lex(VERTICAL_SPACE),
        [["EOL", null], ["IDENTIFIER", "foo"], [":", null], ["EOL", null],
         ["EOL", null], ["INDENT", null], ["IDENTIFIER", "baz"],
         ["DEDENT", null], ["EOL", null], ["EOL", null], ["EOL", null],
         ["IDENTIFIER", "blee"]])

def test_indent_horiz(assert):
    assert.equal(
        lex(HORIZ_SPACE),
        [["EOL", null], ["IDENTIFIER", "foo"], [":", null], ["EOL", null],
         ["INDENT", null], ["IDENTIFIER", "baz"], ["DEDENT", null],
         ["EOL", null], ["IDENTIFIER", "blee"]])


def test_indent_multi(assert):
    assert.equal(
        lex(MULTI_INDENT),
        [["EOL", null], ["IDENTIFIER", "foo"], [":", null],
         ["EOL", null], ["INDENT", null], ["IDENTIFIER", "baz"],
         [":", null], ["EOL", null], ["INDENT", null],
         ["IDENTIFIER", "biz"], ["DEDENT", null], ["DEDENT", null],
         ["EOL", null], ["IDENTIFIER", "blee"]])

def test_indent_unbalanced(assert):
    assert.todo("Fails for unknown reasons")
    assert.throws(fn {lex(UNBALANCED)})
    assert.throws(fn {lex(UNBALANCED2)})

def test_indent_inexpr(assert):
    assert.todo("Fails for unknown reasons")
    assert.throws(fn {lex(PARENS)})

def test_indent_continuation(assert):
    assert.equal(
        lex(CONTINUATION),
        [["EOL", null], ["IDENTIFIER", "foo"], ["(", null],
         ["EOL", null], ["IDENTIFIER", "baz"], ["EOL", null],
         ["IDENTIFIER", "biz"], ["EOL", null], [")", null],
         ["EOL", null], ["IDENTIFIER", "blee"]])

unittest([test_ident, test_char, test_string, test_integer, test_float,
          test_holes, test_braces, test_dot, test_caret, test_plus, test_minus,
          test_colon, test_crunch, test_zap, test_star, test_slash, test_mod,
          test_comment, test_bang, test_eq, test_and, test_or,

          test_indent_simple, test_indent_arrow, test_indent_dedent,
           test_indent_vertical, test_indent_horiz, test_indent_multi,
           test_indent_unbalanced, test_indent_inexpr, test_indent_continuation])
