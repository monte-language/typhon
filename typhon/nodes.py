from typhon.objects import (ConstListObject, IntObject, NullObject,
                            ScriptObject, StrObject)


class Node(object):

    def __repr__(self):
        return self.repr()

    def repr(self):
        assert False, "Inconceivable!"

    def evaluate(self, env):
        raise NotImplementedError


class _Null(Node):

    def repr(self):
        return "<null>"

    def evaluate(self, env):
        return NullObject


Null = _Null()


def nullToNone(node):
    return None if node is Null else node


class Int(Node):

    def __init__(self, i):
        self._i = i

    def repr(self):
        return "%d" % self._i

    def evaluate(self, env):
        return IntObject(self._i)


class Str(Node):

    def __init__(self, s):
        self._s = s

    def repr(self):
        return '"%s"' % (self._s.encode("utf-8"))

    def evaluate(self, env):
        return StrObject(self._s)


class Double(Node):

    def __init__(self, d):
        self._d = d

    def repr(self):
        return "%f" % self._d


class Char(Node):

    def __init__(self, c):
        self._c = c

    def repr(self):
        return "'%s'" % (self._c.encode("utf-8"))


class Tuple(Node):

    def __init__(self, t):
        self._t = t

    def repr(self):
        buf = "["
        buf += ", ".join([item.repr() for item in self._t])
        buf += "]"
        return buf

    def evaluate(self, env):
        return ConstListObject([item.evaluate(env) for item in self._t])


class Call(Node):

    def __init__(self, target, verb, args):
        self._target = target
        self._verb = verb
        self._args = args

    def repr(self):
        buf = "Call(" + self._target.repr() + ", " + self._verb.repr()
        buf += ", " + self._args.repr() + ")"
        return buf

    def evaluate(self, env):
        # There's a careful order of operations here. First we have to
        # evaluate the target, then the verb, and finally the arguments.
        # Once we do all that, we make the actual call.
        target = self._target.evaluate(env)
        verb = self._verb.evaluate(env)
        assert isinstance(verb, StrObject), "non-Str verb"
        args = self._args.evaluate(env)
        assert isinstance(args, ConstListObject), "non-List arguments"

        return target.recv(verb._s, args._l)


class Def(Node):

    def __init__(self, pattern, ejector, value):
        assert isinstance(pattern, Pattern), "non-Pattern lvalue"
        self._p = pattern
        self._e = nullToNone(ejector)
        self._v = value

    def repr(self):
        if self._e is None:
            buf = "Def(" + self._p.repr() + ", " + self._v.repr() + ")"
        else:
            buf = "Def(" + self._p.repr() + ", " + self._e.repr() + ", "
            buf += self._v.repr() + ")"
        return buf

    def evaluate(self, env):
        rval = self._v.evaluate(env)
        # We don't care about whether we only get partway through the pattern
        # unification here before exiting on failure, since we're going to
        # exit this scope on failure before those names can even be used.
        if not self._p.unify(rval, env):
            # XXX if self._p is None
            raise RuntimeError
        return rval


class Noun(Node):

    def __init__(self, noun):
        assert isinstance(noun, Str), "non-Str Noun"
        self._n = noun._s

    def repr(self):
        return "Noun(" + self._n.encode("utf-8") + ")"

    def evaluate(self, env):
        return env.find(self._n)


class Obj(Node):

    def __init__(self, doc, name, auditors, script):
        assert isinstance(auditors, Tuple), "malformed auditors"
        self._d = doc
        self._n = name
        self._as = auditors._t[0]
        self._implements = auditors._t[1:]
        self._s = script

    def repr(self):
        return "Obj(" + self._n.repr() + ")"

    def evaluate(self, env):
        return ScriptObject(self._s)


class Sequence(Node):

    def __init__(self, t):
        assert isinstance(t, Tuple), "Bad Sequence"
        self._t = t

    def repr(self):
        buf = "Sequence("
        buf += self._t.repr()
        buf += ")"
        return buf

    def evaluate(self, env):
        rv = NullObject
        for node in self._t._t:
            rv = node.evaluate(env)
        return rv


# Tag is a transitional node; it doesn't actually do anything, but it's here
# nonetheless because I was too lazy to crank out nodes for every single bit
# of the AST in advance. It will go away real soon.
class Tag(Node):

    def __init__(self, tag, args):
        self._tag = tag
        self._args = args

    def repr(self):
        buf = self._tag + "("
        buf += ", ".join([item.repr() for item in self._args])
        buf += ")"
        return buf

    def evaluate(self, env):
        print "Not evaluating Tag", self._tag
        raise NotImplementedError


class Pattern(Node):
    pass


class FinalPattern(Pattern):

    def __init__(self, noun, guard):
        assert isinstance(noun, Noun), "non-Noun noun!?"
        self._n = noun
        self._g = nullToNone(guard)

    def repr(self):
        if self._g is None:
            return "Final(" + self._n.repr() + ")"
        else:
            return "Final(" + self._n.repr() + " :" + self._g.repr() + ")"

    def unify(self, specimen, env):
        env.record(self._n._n, specimen)
        return True


class IgnorePattern(Pattern):

    def __init__(self, guard):
        self._g = nullToNone(guard)

    def repr(self):
        if self._g is None:
            return "_"
        else:
            return "_ :" + self._g.repr()

    def unify(self, specimen, env):
        return True


class ListPattern(Pattern):

    def __init__(self, patterns, tail):
        assert isinstance(patterns, Tuple), "non-Tuple in ListPattern"
        self._ps = patterns._t
        self._t = nullToNone(tail)

    def repr(self):
        buf = "[" + ", ".join([item.repr() for item in self._ps]) + "]"
        if self._t is not None:
            buf += " | " + self._t.repr()
        return buf

    def unify(self, specimen, env):
        patterns = self._ps
        tail = self._t

        # Can't unify lists and non-lists.
        if not isinstance(specimen, ConstListObject):
            return False
        items = specimen._l

        # If we have no tail, then unification isn't going to work if the
        # lists are of differing lengths.
        if tail is None and len(patterns) != len(items):
            return False
        # Even if there's a tail, there must be at least as many elements in
        # the pattern list as there are in the specimen list.
        elif len(patterns) > len(items):
            return False

        # Actually unify. Because of the above checks, this shouldn't run
        # ragged.
        for i, pattern in enumerate(patterns):
            pattern.unify(items[i], env)

        # And unify the tail as well.
        if tail is not None:
            remainder = ConstListObject(items[len(patterns):])
            tail.unify(remainder, env)

        return True


class VarPattern(Pattern):

    def __init__(self, noun, guard):
        assert isinstance(noun, Noun), "non-Noun noun!?"
        self._n = noun
        self._g = nullToNone(guard)

    def repr(self):
        if self._g is None:
            return "Var(" + self._n.repr() + ")"
        else:
            return "Var(" + self._n.repr() + " :" + self._g.repr() + ")"

    def unify(self, specimen, env):
        env.record(self._n._n, specimen)
        return True

    ('ViaPattern', 2),
    ('BindingPattern', 1),
