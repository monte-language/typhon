```
import "lib/codec/base64" =~ [=> Base64]
import "lib/incant" =~ [=> packScroll, => unpackScroll]
import "lib/streams" =~ [=> collectBytes]
exports (main)
```

```
def formatPK(key) :Str as DeepFrozen:
    return Base64.encode(key.asBytes(), null)
```

This is a basic riff on the [Warner
Spellserver](http://www.lothar.com/blog/58-The-Spellserver/). It receives an
encrypted command to execute arbitrary code, and returns the encrypted result.

Ideally, this could be run over TCP, like:

    socat tcp-listen:8080,fork,reuseaddr exec:'monte eval spellserver.mt.md secret.key'

But we don't properly half-close our connections.

```
def main(argv, => currentRuntime, => makeFileResource, => stdio) as DeepFrozen:
    def keyfile := makeFileResource(argv.last()).getContents()
    def packedScroll := collectBytes(stdio<-stdin())
    def stdout := stdio<-stdout()

    def keyMaker := currentRuntime.getCrypt().keyMaker()

    return when (keyfile, packedScroll) ->
        def ourSK := keyMaker.fromSecretBytes(keyfile)
        def ourPK := ourSK.publicKey()
        traceln(`Spellserver ${formatPK(ourPK)}`)
        def [=> pubkey,
             => nonce,
             => scroll] := unpackScroll(packedScroll)
        def theirPK := keyMaker.fromPublicBytes(pubkey)
        traceln(`Unpacking scroll from ${formatPK(theirPK)}`)
        def keypair := ourSK.pairWith(theirPK)
        def spell := keypair.unseal(scroll, nonce)
        traceln(`MAST spell: ${spell.size()} bytes`)

        def filename :Str := "<incanted spell>"
        def expr := readMAST(spell, => filename)
        traceln(`Casting spell…`)
        when (def bs := eval(expr, safeScope)) ->
            traceln(`Spell was cast, returning ${bs.size()} bytes`)
            def response := packScroll(ourPK.asBytes(), keypair, bs)
            stdout<-(response)
            when (stdout<-complete()) -> { 0 }
```
