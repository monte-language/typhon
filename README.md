
## Porting Notes

  - docstrings: converted to `#` style with an emacs emacs keyboard
    macro using comment-region
    - ISSUE: how to convert to monte docstrings?
  - def -> object
  - comment out DEBuilderOf module decl
  - :[g1, g2] -> :Pair[g1, g2]
  - :generic(g) -> :generic[g]
  - :g[] -> :List[g]
  - :(g1 | g2) -> :Any[g1, g2]
  - <scheme:rest> -> scheme_uriGetter("rest")
    - def N := <scheme:rest> ->
      import "rest" =~ [=>N :DeepFrozen]
  - for pat in expr -> for pat in (expr)

  - datatype names: capitalize int, char;
    float64 -> Double, String -> Str, boolean -> Bool
  - guard names: capitalize any, near, void, nullOk
  - syntax helpers: one `_` for `__makeList`, `__makeInt`
  - E.toQuote -> M.toQuote
    - TODO: E.call(rx, verb, args) to M.call(rx, verb, args, nargs)

