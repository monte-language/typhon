exports (makeMixer)

# A basic optimizer for Kernel-Monte.

# Optimizations considered:
# https://www.clear.rice.edu/comp512/Lectures/Papers/1971-allen-catalog.pdf

# We don't implement:
# * Loop unrolling
# * Loop fusion
# * Common subexpression elimination
# * Code motion
# * Hoisting
# * Strength reduction (or anything lower-level)

# We implement:
# * Constant folding
# * Dead code elimination

# Data model:
# Greens are [liveValue, deopt, span] triple; liveValue is a live mutable
# value, and deopt is an ejector that can be fired to turn this green into a
# red.
# Reds are (atomic?) AST fragments.

def isGreen(rv) :Bool as DeepFrozen:
    return rv =~ [_, _, _]

def areGreen(rvs) :Bool as DeepFrozen:
    for rv in (rvs):
        if (!isGreen(rv)):
            return false
    return true

def makeResidualizer(builder, rbasis) as DeepFrozen:
    return def residualize(rv):
        return if (rv =~ [green, deopt, span]) {
            def go(v) {
                return switch (v) {
                    match l :Any[Char, Double, Int, Str] {
                        builder.LiteralExpr(l, span)
                    }
                    match via (rbasis.fetch) n { builder.NounExpr(n, span) }
                    match l :List {
                        builder.MethodCallExpr(builder.NounExpr("_makeList", span), "run",
                                         [for r in (l) go(r)], [], span)
                    }
                    # XXX Bytes?
                    # XXX Transparent/uncall?
                    match _ { throw.eject(deopt, `Couldn't residualize $green`) }
                }
            }
            go(green)
        } else { rv }

def makeMixer(anf, reductionBasis) as DeepFrozen:
    var counter := 0
    def residualize := makeResidualizer(anf, reductionBasis)

    def atomize(val, k):
        # val is a green or red, k expects residualized atom
        def rv := residualize(val)
        return rv.walk(object atomizer {
            match [constructor, args, _] {
                switch (constructor) {
                    # XXX uh? style?
                    match =="Atom" { k(args[0]) }
                    match =="LiteralExpr" { k(rv) }
                    match =="NounExpr" { k(rv) }
                    match =="BindingExpr" { k(rv) }
                    # XXX need to walk under script?
                    match =="ObjectExpr" { k(rv) }
                    match _ {
                        counter += 1
                        def t := `_temp_mixer_sym$counter`
                        def span := args.last()
                        def noun := anf.NounExpr(t, span)
                        anf.LetExpr(anf.FinalPattern(t, span), rv, k(noun),
                                    span)
                    }
                }
            }
        })

    def atomizes(vals, k):
        return if (vals =~ [val] + rest) {
            atomize(val, fn v {
                atomizes(rest, fn vs { k([v] + vs) })
            })
        } else { k([]) }

    def atom(a, frame, k):
        return a.walk(object atomWalker {
            to LiteralExpr(value, span) {
                return escape deopt { k([value, deopt, span]) } catch _ {
                    k(anf.LiteralExpr(value, span))
                }
            }

            # XXX factor out shared code with NounExpr?
            to BindingExpr(name :Str, span) {
                return switch (`&&$name`) {
                    match via (frame.fetch) green { k(green) }
                    match via (reductionBasis.fetch) outer {
                        escape deopt { k([outer, deopt, span]) } catch _ {
                            k(anf.BindingExpr(name, span))
                        }
                    }
                    match _ { k(anf.BindingExpr(name, span)) }
                }
            }

            to NounExpr(name :Str, span) {
                return switch (`&&$name`) {
                    match via (frame.fetch) [&&green, deopt, span] {
                        k([green, deopt, span])
                    }
                    match via (reductionBasis.fetch) &&outer {
                        escape deopt { k([outer, deopt, span]) } catch _ {
                            k(anf.NounExpr(name, span))
                        }
                    }
                    match _ { k(anf.NounExpr(name, span)) }
                }
            }

            to ObjectExpr(docstring, name, asExpr, auditors, script, span) {
                return k(anf.ObjectExpr(docstring, name, asExpr, auditors,
                                        script, span))
            }
        })

    def atoms(ats, frame, k):
        return if (ats =~ [a] + rest) {
            atom(a, frame, fn val {
                atoms(rest, frame, fn vals { k([val] + vals) })
            })
        } else { k([]) }

    return object mixer:
        to mix(expr, frame):
            return expr.walk(mixer(frame, residualize))

        to matchBind(specimen, frame, k):
            return object matchBinder:
                to IgnorePattern(span):
                    return if (isGreen(specimen)) { k(frame) } else {
                        anf.LetExpr(anf.IgnorePattern(span),
                                    residualize(specimen), k(frame), span)
                    }

                to BindingPattern(noun :Str, span):
                    return if (isGreen(specimen)) {
                        k(frame.with(`&&$noun`, specimen))
                    } else {
                        anf.LetExpr(anf.BindingPattern(noun, span),
                                    residualize(specimen), k(frame), span)
                    }

                to FinalPattern(noun :Str, guard, span):
                    return if (specimen =~ [green, deopt, span]) {
                        k(frame.with(`&&$noun`, [&&green, deopt, span]))
                    } else {
                        anf.LetExpr(anf.FinalPattern(noun, guard, span),
                                    residualize(specimen), k(frame), span)
                    }

        to run(frame, k):
            # k wants a green or red; reds must be complex
            return object walker:
                to Atom(a, span):
                    return atom(a, frame, fn rv {
                        k(if (isGreen(rv)) { rv } else { anf.Atom(rv, span) })
                    })

                to LetExpr(patt, expr, body, span):
                    return expr.walk(mixer(frame, fn e {
                        patt.walk(mixer.matchBind(e, frame, fn f {
                            body.walk(mixer(f, k))
                        }))
                    }))

                to MethodCallExpr(receiver, verb :Str, arguments :List, namedArgs,
                                  span):
                    return atoms([receiver] + arguments, frame, fn [r] + args {
                        escape deopt {
                            if (areGreen([r] + args)) {
                                try {
                                    def rv := M.call(r[0], verb,
                                                     [for arg in (args) arg[0]],
                                                     [].asMap())
                                    k([rv, deopt, span])
                                } catch _ { deopt() }
                            } else { deopt() }
                        } catch _ {
                            atomizes([r] + args, fn [receiverAtom] + argAtoms {
                                k(anf.MethodCallExpr(receiverAtom,
                                                     verb, argAtoms,
                                                     namedArgs, span))
                            })
                        }
                    })
