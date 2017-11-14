import "lib/capnp" =~ [=> makeMessage :DeepFrozen]
import "lib/codec/utf8" =~ [=> UTF8 :DeepFrozen]
exports (CodeGeneratorRequest)

def text(pointer) as DeepFrozen:
    return if (pointer == null):
        null
    else:
        def bs := _makeBytes.fromInts(_makeList.fromIterable(pointer))
        def s := UTF8.decode(bs, null)
        # Slice off the trailing NULL byte.
        s.slice(0, s.size() - 1)

def Node(root) as DeepFrozen:
    return object node:
        to id():
            return root.getWord(0)
        to displayName():
            return text(root.getPointer(0))

def CodeGeneratorRequest.unpack(bs :Bytes) as DeepFrozen:
    def root := makeMessage(bs).getRoot()
    traceln(`root $root`)
    return object cgr:
        to nodes():
            return [for r in (root.getPointer(0)) Node(r)]
        to requestedFiles():
            return root.getPointer(1)
