def [auditorStampSealer :DeepFrozen,
     auditorStampUnsealer :DeepFrozen] := makeBrandPair("mitm auditor stamps")

def mitmAuditedBy(auditor, specimen) as DeepFrozen:
    if (_auditedBy(auditor, specimen)):
        return true
    def box := specimen._sealedDispatch(auditorStampSealer)
    try:
        def stamps := auditorStampUnsealer.unseal(box)
        return stamps.contains(auditor)
    catch p:
        return false

def makeMitmObject(auditors, ast, methods, matchers, fqn, oEnv) as DeepFrozen:
    def auditMitmObject():
        return object mitmAuditor:
            to audit(audition):
                for a in (auditors):
                    audition.ask(a)
                return false

    def mitmDispatch(mitmObject, verb, args, kwargs) as DeepFrozen:
        # # Have to do this before regular dispatch because it's not overridable behavior.
        # if (verb == "_sealedDispatch" && args == [auditorStampSealer]):
        #     return auditorStampSealer.seal(stamps)
        for m in (methods):
            var methEnv := oEnv
            if (verb == m.getVerb()):
                if (m.getPatterns().size() != args.size()):
                    throw(`${fqn}.${verb} requires ${m.getPatterns().size()} arguments, given ${args.size()}`)
                for [p, a] in (zip(m.getPatterns(), args)):
                    def newEnv := matchBind(p, a, methEnv, throw)
                    methEnv := newEnv
                for np in (m.getNamedPatterns()):
                    def dflt := np.getDefault()
                    def arg := kwargs.fetch(np.getKey(), fn {
                        if (dflt != null) {dflt} else {
                                throw(`${fqn}.${verb} requires named arg "${np.getKey()}"`)
                                }})
                    def newEnv := matchBind(np.getPattern(), arg, methEnv, throw)
                    methEnv := newEnv
                def [ResultGuard, rgEnv] := if (m.getResultGuard() == null) {
                    [Any, methEnv]
                } else {
                    _eval(m.getResultGuard(), fqn, methEnv)
                }
                def result :ResultGuard := _eval(m.getBody(), fqn, rgEnv)
                return result
        # do we have a miranda method for this verb?
        switch ([verb] + args):
            match [=="_conformTo", guard]:
                return mitmObject
            match [=="_getAllegedInterface"]:
                # XXX do the computedinterface thing
                return null
            match [=="_printOn", out]:
                out.print(`<MITM: $fqn>`)
            match [=="_respondsTo", verb, arity]:
                for m in (methods):
                    if (m.getVerb() == verb && m.getPatterns().size() == arity):
                        return true
                return (matchers.size() == 0)
            match [=="_sealedDispatch", sealer]:
                return null
            match ["_uncall"]:
                return null
            match ["_whenMoreResolved", callback]:
                callback <- (mitmObject)
                return null
            match _:
                null
        # ok so we didn't find a method that handles this
        for m in (matchers):
            escape e:
                def newEnv := matchBind(m.getPattern(), [verb, args, kwargs], oEnv, e)
                return _eval(m.getBody(), fqn, newEnv)
        throw(`Message refused: ${fqn}.${verb}/${args.size()}`)

    # The paradigmatic use case for plumbing exprs. Oh well.
    bind mitmObject implements auditMitmObject():
        to _conformTo(guard):
            return mitmDispatch(mitmObject, "_conformTo", [guard], [].asMap())
        to _getAllegedInterface():
            return mitmDispatch(mitmObject, "_getAllegedInterface", [], [].asMap())
        to _printOn(out):
            mitmDispatch(mitmObject, "_printOn", [], [].asMap())
        to _respondsTo(verb, arity):
            return mitmDispatch(mitmObject, "_respondsTo", [verb, arity], [].asMap())
        to _sealedDispatch(sealer):
            return mitmDispatch(mitmObject, "_sealedDispatch", [sealer], [].asMap())
        to _uncall():
            return mitmDispatch(mitmObject, "_uncall", [], [].asMap())
        to _whenMoreResolved(callback):
            return mitmDispatch(mitmObject, "_whenMoreResolved", [callback], [].asMap())

        match [verb, args, kwargs]:
            mitmDispatch(mitmObject, verb, args, kwargs)

    return mitmObject

def mitmEval(expr, outers):
    
