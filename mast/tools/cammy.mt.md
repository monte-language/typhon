```
exports (main)
```

# Cammy: A simple low-level CAM

We compile categorical expressions to a concrete implementation of the
Categorical Abstract Machine, or CAM. We follow [Bonn
1993](https://citeseerx.ist.psu.edu/viewdoc/summary?doi=10.1.1.71.3358)'s
expository bytecodes as a starting point.

## Optimized Bytecode Writing

We implement a basic finite-state machine which examines recently-pushed
bytecodes on each label and ponders whether to rewrite them.

These bytecodes do not alter the stack, just the register.

```
def noStackEffect :Bytes := _makeBytes.fromInts([0, 1])
```

```
def makeBytecodeWriter() as DeepFrozen:
    def labels := [].diverge()
    return object bytecodeWriter:
        to freshLabel():
            def insts := [].diverge(0..255)
            labels.push(insts)
            return object codeMachine:
                to nop():
                    insts.push(0)
                to clear():
                    # Register effect only, so coalesce
                    while (!insts.isEmpty() && noStackEffect.contains(insts.last())):
                        insts.pop()
                    insts.push(1)

        to export():
            return b``.join([for label in (labels) _makeBytes.fromInts(label)])
```

## Compilation

Our compiler has some extra recursion in order to make composition
transparent. The compiler generates a fresh label for each individual functor
application, but reuses the label for composition so that both pieces of the
composed function are agnostic to where they've been located.

```
def compileTop(expr) as DeepFrozen:
    def writer := makeBytecodeWriter()
    def compile(tree, label):
        switch (tree):
            match [=="id"]:
                label.nop()
            match [=="comp", f, g]:
                compile(f, label)
                compile(g, label)
            match [=="!"]:
                label.clear()
    compile(expr, writer.freshLabel())
    return writer.export()
```

## Entrypoint

```
def main(argv, => makeFileResource) as DeepFrozen:
    def outFile := argv.last()
    if (!outFile.endsWith(".cam")):
        throw(`Bad filename $outFile doesn't end with .cam`)
    def expr := ["comp", ["id"], ["!"]]
    def bs := b`Cammy000` + compileTop(expr)
    traceln("Compiled", bs)
    return when (makeFileResource(outFile)<-setContents(bs)) -> { 0 }
```
