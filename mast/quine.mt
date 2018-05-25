import "lib/codec/utf8" =~ [=> UTF8]
import "meta" =~ [=> this]
exports (main)
def main(_argv, => stdio) as DeepFrozen:
    return when (stdio.stdout()<-(UTF8.encode(this.source(), null))) -> { 0 }
