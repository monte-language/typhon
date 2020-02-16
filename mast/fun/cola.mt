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
        traceln(`bump($size) -> $rv (${size + rv})`)
        return rv

    def internStr(symbol :Str) :Int:
        return interned.fetch(symbol, fn {
            def rv := interned[symbol] := bump(1)
            uninterned[rv] := symbol
            traceln(`intern($symbol) -> $rv`)
            rv
        })

    def intern(_self, args :List[Int]) :Int:
        return internStr(_makeStr.fromChars([for c in (args) '\x00' + c]))

    def lookup :Int := internStr("lookup")
    
    def DELEGATED_STR :Int := bump(1)
    heap[DELEGATED_STR] := "delegated".size()
    for c in ("delegated") { heap[bump(1)] := c.asInteger() }

    # This implementation determines vtable layout. We'll start with something
    # naive but easy to extend:
    # [ parent | next ]
    # parent is 0 if no parent. next points to the tail of a linked list:
    # [ kn | vn | next ]
    # In both cases, next is 0 if there's no more methods.
    def doLookup(self :Int, symbol :Int) :Int:
        def parent := heap[self]
        var next := self + 1
        while (next != 0):
            if (heap[next] == symbol):
                return heap[next + 1]
            next := heap[next + 2]
        return if (parent == 0) { 0 } else { doLookup(parent, symbol) }

    def addMethod(self :Int, selector :Int, meth :Int):
        var next := self + 1
        while (next != 0):
            if (heap[next] == selector):
                traceln(`replacing addMethod($self, $selector, $meth)`)
                heap[next + 1] := meth
                return 0
            if (heap[next + 2] == 0):
                traceln(`new addMethod($self, $selector, $meth)`)
                def link := bump(3)
                heap[link] := selector
                heap[link + 1] := meth
                heap[next + 2] := link
                return 0
            next := heap[next + 2]

    def allocate(self :Int, size :Int) :Int:
        def obj := bump(1 + size * 3) + 1
        heap[obj - 1] := self
        # Pre-link the vtable, so that it can be traversed.
        for i in (0..!size):
            def next := obj + 3 * i + 2
            heap[next] := next + 1
        traceln(`allocate($self, $size) -> $obj`)
        return obj

    def delegated(self :Int) :Int:
        def child :Int := allocate(if (self == 0) { 0 } else { heap[self - 1] }, 2)
        heap[child] := self
        traceln(`delegated($self) -> $child`)
        return child

    # 0
    def vtableVT :Int := delegated(0)

    def meths := [
        LOOKUP => fn self, args { doLookup(self, args[0]) },
        ADD_METHOD => fn self, args { addMethod(self, args[0], args[1]) },
        ALLOCATE => fn self, args { allocate(self, args[0]) },
        INTERN => intern,
        DELEGATED => fn self, _ { delegated(self) },
    ]

    # We must define send() after allocating the first vtable.
    def send(obj :Int, selector :Int, args :List[Int]):
        def vt := heap[obj - 1]
        def meth := if (selector == lookup && obj == vtableVT) {
            doLookup(vt, lookup)
        } else { send(vt, lookup, [selector]) }
        return meths[meth](obj, args)

    def dump(label :Str, vt :Int):
        def parent := heap[vt]
        def selectors := [].diverge()
        var next := vt + 1
        while (next != 0):
            selectors.push(switch (heap[next]) {
                match ==0 { break }
                match via (uninterned.fetch) s { s }
                match i { `<raw value $i>` }
            })
            next := heap[next + 2]
        traceln(`$label: VT at $vt (parent $parent) selectors ${selectors.snapshot()}`)

    # 1
    heap[vtableVT - 1] := vtableVT

    dump("vtable", vtableVT)

    def objectVT :Int := delegated(0)
    heap[objectVT - 1] := vtableVT
    heap[vtableVT + 1] := objectVT

    dump("object", objectVT)

    def symbolVT :Int := delegated(objectVT)

    dump("symbol", symbolVT)

    # 2
    addMethod(vtableVT, internStr("lookup"), LOOKUP)

    dump("vtable", vtableVT)

    # 3
    addMethod(vtableVT, internStr("addMethod"), ADD_METHOD)

    dump("vtable", vtableVT)

    # 4
    addMethod(vtableVT, internStr("allocate"), ALLOCATE)

    dump("vtable", vtableVT)

    def symbol :Int := send(vtableVT, internStr("allocate"), [1])

    # 5
    addMethod(symbolVT, internStr("intern"), INTERN)

    dump("symbol", symbolVT)

    # 6
    def delegatedSelector :Int := send(symbol, internStr("intern"),
                                       [DELEGATED_STR])
    send(vtableVT, internStr("addMethod"), [delegatedSelector, DELEGATED])

    dump("vtable", vtableVT)

    return object colaWorld:
        to initialScope() :Map[Str, Int]:
            return [
                => symbol,
                => vtableVT,
                => objectVT,
            ]

        to intern(symbol :Str) :Int:
            return internStr(symbol)

        to send(obj :Int, selector :Int, args :List[Int]) :Int:
            return send(obj, selector, args)
