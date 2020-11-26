import "lib/streams" =~ [=> collectBytes]
exports (getNumberOfProcessors)

def getNumberOfProcessors(nproc) :Vow[Int] as DeepFrozen:
    "
    The number of processors available for the current process to use.

    Intended usage is with `lib/which`, passing `which(\"nproc\")`.
    "

    # Kudos to nproc for not requiring any ambient authority.
    def sp := nproc<-([], [].asMap(), "stdout" => true)
    def bs := collectBytes(sp<-stdout())
    return when (bs) ->
        if (bs =~ b`@{via (_makeInt.fromBytes) count}$\n`) { count } else {
            Ref.broken(`nproc returned not a number, but $bs`)
        }
