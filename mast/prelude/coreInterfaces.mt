def compose(f :DeepFrozen, g :DeepFrozen):
    "Compose two objects together.

     This composite object passes messages to `f`, except for those which
     raise exceptions, which are passed to `g` instead."

    return object composition as DeepFrozen:
        match message:
            try:
                M.callWithMessage(f, message)
            catch _:
                M.callWithMessage(g, message)


interface coreVoid:
    "The void."


interface coreBool:
    "The Boolean values."

    to op__cmp(other)

    to and(other)
    to butNot(other)
    to or(other)
    to xor(other)

    to not()

    to pick(ifTrue, ifFalse):
        "Return `ifTrue` if true, else `ifFalse` if false."


[
    "Void" => compose(Void, coreVoid),
    "Bool" => compose(Bool, coreBool),
]
