exports (makeWorld)

# https://www.piumarta.com/software/cola/objmodel2.pdf

def LOOKUP :Int := 0
def ADD_METHOD :Int := 1
def ALLOCATE :Int := 2
def INTERN :Int := 3
def DELEGATED :Int := 4

def makeWorld() as DeepFrozen:
    # NB: 0th index is reserved for nil
    def heap := [0].diverge(Int)
    def interned := [].asMap().diverge(Str, Int)
    def uninterned := [].asMap().diverge(Int, Str)

    def bump(size :Int):
        def rv := heap.size()
        for _ in (0..!size) { heap.push(0) }
        return rv

    def internStr(symbol :Str) :Int:
        return interned.fetch(symbol, fn {
            def rv := interned[symbol] := bump(1)
            uninterned[rv] := symbol
            traceln(`intern($symbol) -> $rv`)
            rv
        })

    def unintern(i :Int) :Str:
        return uninterned.fetch(i, fn { `<raw value $i>` })

    def intern(_self, args :List[Int]) :Int:
        return internStr(_makeStr.fromChars([for c in (args) '\x00' + c]))

    def lookup :Int := internStr("lookup")
    
    def DELEGATED_STR :Int := bump(1)
    heap[DELEGATED_STR] := "delegated".size()
    for c in ("delegated") { heap[bump(1)] := c.asInteger() }

    def walkHeapList(start :Int):
        if (start == 0) { return [] }
        return def listWalker._makeIterator():
            var next := start
            return def listerator.next(ej):
                if (next == 0) { throw.eject(ej, "End of list") }
                def k := heap[next]
                def v := heap[next + 1]
                def rv := [next, [k, v]]
                next := heap[next + 2]
                return rv

    # This implementation determines vtable layout. We'll start with something
    # naive but easy to extend:
    # [ parent | next ]
    # parent is 0 if no parent. next points to the tail of a linked list:
    # [ kn | vn | next ]
    # In both cases, next is 0 if there's no more methods.
    def doLookup(self :Int, selector :Int) :Int:
        def parent := heap[self]
        for [k, v] in (walkHeapList(heap[self + 1])):
            if (k == selector):
                return v
        return if (parent == 0) { 0 } else { doLookup(parent, selector) }

    def addMethod(self :Int, selector :Int, meth :Int):
        def start := heap[self + 1]
        if (start == 0):
            traceln(`first addMethod($self, $selector, $meth)`)
            def new := bump(3)
            heap[new] := selector
            heap[new + 1] := meth
            heap[self + 1] := new
            return 0
        var last := 0
        for link => [k, _] in (walkHeapList(heap[self + 1])):
            if (k == selector):
                traceln(`replacing addMethod($self, $selector, $meth)`)
                heap[link + 1] := meth
                return 0
            last := link
        traceln(`new addMethod($self, $selector, $meth)`)
        def new := bump(3)
        heap[new] := selector
        heap[new + 1] := meth
        heap[last + 2] := new
        return 0

    def allocate(self :Int, size :Int) :Int:
        # The end of the table is a raw data region of the given size.
        # [ vtable || data ... ]
        # Return pointer points directly to the start of the vtable, which is
        # one word in.
        def obj := bump(1 + size)
        heap[obj] := self
        traceln(`allocate($self, $size) -> $obj`)
        return obj

    def delegated(self :Int) :Int:
        # We now need to reserve two words of data for the vtable's own data.
        # [ vtable || parent | next | data ... ]
        def child :Int := allocate(if (self == 0) { 0 } else { heap[self] }, 2)
        heap[child] := self
        traceln(`delegated($self) -> $child`)
        return child

    # 0
    # The "vtable of vtables". This degenerate object has an identity, but no
    # vtable of its own. Instead, it has one single behavior, lookup, which is
    # hardcoded into send().
    def vtvt :Int := delegated(0)
    heap[vtvt] := vtvt

    def meths := [
        LOOKUP => fn self, args { doLookup(self, args[0]) },
        ADD_METHOD => fn self, args { addMethod(self, args[0], args[1]) },
        ALLOCATE => fn self, args { allocate(self, args[0]) },
        INTERN => intern,
        DELEGATED => fn self, _ { delegated(self) },
    ]

    # We must define send() after allocating the vtable of vtables, since we
    # need to special-case sends to it.
    def send(obj :Int, selector :Int, args :List[Int]):
        if (obj == 0) { return 0 }
        def vt := heap[obj]
        def meth := if (selector == lookup && obj == vtvt) {
            doLookup(vt, lookup)
        } else { send(vt, lookup, [selector]) }
        def rv := meths[meth](obj, args)
        traceln(`send($obj, ${unintern(selector)}, $args) -> $rv`)
        return rv

    def dump(label :Str, self :Int):
        def vt := heap[self]
        def parent := heap[vt]
        def selectors := [for [k, _] in (walkHeapList(heap[vt + 1])) unintern(k)]
        traceln(`$label: Object at $self, VT at $vt (parent $parent) selectors $selectors`)

    # 1
    def objectVT :Int := delegated(0)
    def symbolVT :Int := delegated(objectVT)
    def vtableVT :Int := delegated(objectVT)

    def vtable := delegated(0)
    heap[vtable] := vtableVT

    def obj := allocate(objectVT, 0)

    dump("vtableVT", vtableVT)
    dump("vtable", vtable)
    dump("symbolVT", symbolVT)
    dump("objectVT", objectVT)
    dump("object", obj)

    # 2
    addMethod(vtableVT, internStr("lookup"), LOOKUP)

    # 3
    addMethod(vtableVT, internStr("addMethod"), ADD_METHOD)

    # 4
    addMethod(vtableVT, internStr("allocate"), ALLOCATE)

    dump("vtable", vtable)

    def symbol :Int := send(vtable, internStr("allocate"), [0])

    dump("symbol", symbol)

    # 5
    addMethod(symbolVT, internStr("intern"), INTERN)

    dump("symbol", symbol)

    # 6
    def delegatedSelector :Int := send(symbol, internStr("intern"),
                                       [DELEGATED_STR])
    send(vtableVT, internStr("addMethod"), [delegatedSelector, DELEGATED])

    dump("vtable", vtable)

    return object colaWorld:
        to initialScope() :Map[Str, Int]:
            return [
                => symbol,
                => vtable,
                => obj,
            ]

        to intern(symbol :Str) :Int:
            return internStr(symbol)

        to send(obj :Int, selector :Int, args :List[Int]) :Int:
            return send(obj, selector, args)
