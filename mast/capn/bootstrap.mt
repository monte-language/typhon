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

def Brand(_root) as DeepFrozen:
    return object brand {}

def Type(root) as DeepFrozen:
    def which := root.getWord(0) & 0xff
    return object type:
        to _which():
            return which
        to typeId():
            return root.getWord(1)
        to elementType():
            return Type(root.getPointer(0))
        to brand():
            return Brand(root.getPointer(0))

def Field(root) as DeepFrozen:
    def which := root.getWord(1) & 0xff
    return object field:
        to _which():
            return which
        to discriminantValue():
            return root.getWord(0) >> 16 & 0xff
        to name():
            return text(root.getPointer(0))
        to slot():
            return object slot:
                to offset():
                    return root.getWord(0) >> 32
                to type():
                    return Type(root.getPointer(2))

def Node(root) as DeepFrozen:
    def which := root.getWord(1) >> 32 & 0xff
    return object node:
        to _which():
            return which
        to id():
            return root.getWord(0)
        to displayNameLengthPrefix():
            return root.getWord(1) & 0xffff
        to displayName():
            return text(root.getPointer(0))
        to fields():
            return [for r in (root.getPointer(3)) Field(r)]

def CodeGeneratorRequest.unpack(bs :Bytes) as DeepFrozen:
    def root := makeMessage(bs).getRoot()
    traceln(`root $root`)
    return object cgr:
        to nodes():
            return [for r in (root.getPointer(0)) Node(r)]
        to requestedFiles():
            return root.getPointer(1)
