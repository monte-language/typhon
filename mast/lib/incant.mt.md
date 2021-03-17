```
import "lib/codec/base64" =~ [=> Base64]
import "lib/codec/utf8" =~ [=> UTF8]
import "lib/json" =~ [=> JSON]
exports (packScroll, unpackScroll, makeSpellbook)
```

# Spellbooks and Incantations

Programming is like wizardry. Here, we expand a metaphor from
[Warner](http://www.lothar.com/blog/58-The-Spellserver/) and provide tools for
invoking signed code. The main metaphor is that programs are like spells.

## Scrolls

When a spell needs to be transported from one computer to another, we need to
armor it appropriately. A spell is stored as a bytestring, and all of the
cryptographic information which needs to be associated with it is also
represented as bytestrings. Our armor will do three things:

1) Apply Base64 to values in a map, turning them into strings
2) Apply JSON to the entire map, turning it into a string
3) Apply UTF8 to the entire string, turning it into a bytestring

```
def finishScroll(m :Map) :Bytes as DeepFrozen:
    "Finish a scroll."

    def via (JSON.encode) via (UTF8.encode) rv :Bytes := [for k => v in (m) k => {
        Base64.encode(v, null)
    }]
    return rv

def packScroll(pubkey :Bytes, keypair, plaintext :Bytes) :Bytes as DeepFrozen:
    "Pack a scroll into wire-ready JSON."

    def [scroll, nonce] := keypair.seal(plaintext)

    return finishScroll([
        => pubkey,
        => nonce,
        => scroll,
    ])

def unpackScroll(bs :Bytes) :Map as DeepFrozen:
    "Unpack a scroll from bytes to a map."

    def via (UTF8.decode) via (JSON.decode) rv :Map := bs
    return [for k => v in (rv) k => Base64.decode(v, null)]
```

## Spellbooks

A spellbook is a way to address a particular peer. The peer's public key is
paired with a local secret key in order to produce a cryptographic endpoint
which can both send and receive bytestrings.

```
def Ast :DeepFrozen := astBuilder.getAstGuard()

object makeSpellbook as DeepFrozen:
    to fromKeyfile(keyMaker, bs :Bytes):
        "Restore a spellbook from a keyfile."

        def [=> ourSecretKey, => theirPublicKey] := unpackScroll(bs)
        return makeSpellbook(keyMaker.fromSecretBytes(ourSecretKey),
                             keyMaker.fromPublicBytes(theirPublicKey))

    to run(ourSecretKey, theirPublicKey):
        "
        Assemble a spellbook which uses `ourSecretKey` to prepare spells which
        will be interpreted by the holder of `theirPublicKey`.
        "

        def ourPublicKey := ourSecretKey.publicKey()
        def keypair := ourSecretKey.pairWith(theirPublicKey)
        return object spellbook:
            "A tome of peer-to-peer remote code invocation."

            to invoke(spell :Ast) :Bytes:
                "Write `spell` on a scroll."

                def context := makeMASTContext()
                context(spell)
                def scroll :Bytes := context.bytes()
                return packScroll(ourPublicKey.asBytes(), keypair, scroll)

            to decipher(incantation :Bytes) :Bytes:
                "Unpack an `incantation`."

                def [=> nonce, => scroll] | _ := unpackScroll(incantation)
                return keypair.unseal(scroll, nonce)

            to exportKeyfile() :Bytes:
                "Save this spellbook to a keyfile which can be saved to disk."

                return finishScroll([
                    "ourSecretKey" => ourSecretKey.asBytes(),
                    "theirPublicKey" => theirPublicKey.asBytes(),
                ])
```
