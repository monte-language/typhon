exports (Location, Store, makeStore)

# Storage capabilities, based on "Storage Combinators"
# https://www.hpi.uni-potsdam.de/hirschfeld/publications/media/WeiherHirschfeld_2019_StorageCombinators_AcmDL_Preprint.pdf

interface Location :DeepFrozen:
    "A place where values are represented."

    to get():
        "Retrieve a value."

    to put(value) :Vow[Void]:
        "Change the value."

    to merge(new):
        "Update the value with a new value, returning a merged value."

    to delete():
        "Delete the value."

interface Store :DeepFrozen:
    "A resolver of references to locations."

    to run(ref) :Location:
        "Resolve a reference."

def constLeft(x, _) as DeepFrozen { return x }

def id(x) as DeepFrozen { return x }

object makeStore as DeepFrozen:
    "Turn raw collections into structured stores."

    to fromMap(m :Map, => monoid := constLeft) :Store:
        "
        Turn a `Map` into a store.

        The `monoid` controls how merges are performed; by default, it is the
        same behavior as `.or/1`, `fn x, _ { x }`.
        "

        def storage := m.diverge()
        return def mapStore(ref) as Store:
            return object mapLocation as Location:
                to get():
                    return storage[ref]
                to put(value):
                    storage[ref] := value
                to merge(new):
                    def old := storage.fetch(ref, fn {
                        return storage[ref] := new
                    })
                    return storage[ref] := monoid(old, new)
                to delete():
                    storage.removeKey(ref)

    to fromAdjunction(store, ana, kata, => mapRef := id) :Store:
        "
        Transform data as it moves to and from a store.

        `ana` lifts data into the store, and `kata` takes it down from the
        store.

        We would prefer it if `ana` and `kata` were adjoint; that is, if
        applying `ana`, then `kata`, then `ana`, were equivalent to applying
        `ana`, or perhaps vice versa.

        When `ana` is an encoder, and `kata` is a decoder, then this method
        builds a codec. When `ana` is a serializer and `kata` is a
        deserializer, then this method builds a serde.

        `mapRef` transforms references before they are sent to `store`; by
        default, it is `fn x { x }`.
        "

        return def adjointStore(ref) as Store:
            def loc := store<-(mapRef(ref))
            return object adjointLocation as Location:
                to get():
                    return when (def p := loc<-get()) -> { kata(p) }
                to put(value):
                    return loc<-put(ana(value))
                to merge(new):
                    return when (def p := loc<-merge(ana(new))) -> {
                        kata(p)
                    }
                to delete():
                    return loc<-delete()

    to writingThrough(core :Vow[Store], cache :Vow[Store]) :Store:
        "
        Wrap access to `core` with access to `cache`. Reads to `core` will be
        copied to `cache`; writes to `core` will write through `cache`.

        As the names suggest, this method is meant to implement write-through
        caching architectures. However, it is suitable for any sort of
        write-through arrangement, regardless of whether `cache` is durable.
        "

        return def writeThroughStore(ref) as Store:
            def coreLoc := core<-(ref)
            def cacheLoc := cache<-(ref)
            def copy():
                return when (def p := coreLoc<-get()) -> { cacheLoc<-put(p) }
            return object writeThroughLocation as Location:
                to get():
                    return when (def p := cacheLoc<-get()) -> { p } catch _ {
                        copy()
                    }
                to put(value):
                    return when (coreLoc<-put(value),
                                 cacheLoc<-put(value)) -> { null }
                to merge(new):
                    return when (copy()) -> {
                        when (def p := cacheLoc<-merge(new)) -> {
                            cacheLoc<-put(p)
                        }
                    }
                to delete():
                    return when (coreLoc<-delete(),
                                 cacheLoc<-delete()) -> { null }

    to applyingCodec(store :Store, codec :DeepFrozen) :Store:
        def ana(value, => FAIL) { return codec.encode(value, FAIL) }
        def kata(value, => FAIL) { return codec.decode(value, FAIL) }
        return makeStore.fromAdjunction(store, ana, kata)
