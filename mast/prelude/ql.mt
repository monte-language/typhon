# Utilities for constructing QPs.

def tokensOf(pieces, makeLexer) as DeepFrozen:
    var rv := []
    for piece in pieces:
        # Yes, this will pick up value and pattern holes which are
        # strings. However, this is a feature; presumably, if your
        # lexer and parser prefer to handle holes this way, then this
        # is exactly what was intended.
        if (piece =~ s :Str):
            def lexer := makeLexer()
            lexer.feedMany(s)
            if (lexer.failed()):
                throw("Failed to lex QL piece " + M.toQuote(s) +
                      ": " + lexer.getFailure())
            else if (!lexer.finished()):
                throw("Incomplete QL piece " + M.toQuote(s))
            else:
                # Well, it didn't fail, so it succeeded, right?
                def results := lexer.results()
                rv += results
        else:
            rv with= (piece)
    return rv

def makeLexerQP(makeQL :DeepFrozen, makeLexer :DeepFrozen,
                makeValueHole :DeepFrozen, makePatternHole :DeepFrozen):
    return object lexerQP as DeepFrozen:
        to valueHole(index :Int):
            return makeValueHole(index)

        to patternHole(index :Int):
            return makePatternHole(index)

        to valueMaker(pieces):
            def tokens := tokensOf(pieces, makeLexer)
            return makeQL(tokens)

        to matchMaker(pieces):
            def tokens := tokensOf(pieces, makeLexer)
            return makeQL(tokens)

[=> makeLexerQP]
