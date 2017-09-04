
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
  - for pat in expr -> for pat in (expr)
