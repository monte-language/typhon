import "lib/atoi" =~ _
import "lib/entropy/pool" =~ _
import "lib/enum" =~ _
# Needs fake Timer.
# ::"import".script("lib/irc/client")

## Depends on derp, not in the repo.
# ::"import".script("lib/parsers/http")
import "lib/parsers/marley" =~ _
import "lib/codec/percent" =~ _
import "lib/record" =~ _
import "tools/infer" =~ _
import "lib/json" =~ _
import "tests/proptests" =~ _
exports ()

def bench(_, _) as DeepFrozen:
    return null

::"import".script("lib/singleUse")
::"import".script("lib/slow/exp", [=> &&bench])
::"import".script("lib/words")
::"import".script("fun/elements")
::"import".script("tests/auditors")
::"import".script("tests/fail-arg")
::"import".script("tests/lexer")
::"import".script("tests/parser")
::"import".script("tests/expander")
::"import".script("tests/optimizer")
::"import".script("tests/flexMap")
::"import".script("lib/paths")
::"import".script("lib/irc/user")
::"import".script("lib/monte/monte_optimizer")
::"import".script("lib/netstring")
::"import".script("lib/parsers/html")
::"import".script("lib/cache")
::"import".script("lib/codec/utf8")
::"import".script("lib/continued", [=> &&bench])
