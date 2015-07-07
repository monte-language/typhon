def [=> UTF8] | _ := import("lib/codec/utf8")
def [=> tag] | _ := import("lib/http/tag")


def smallBody(s):
    escape badBody:
        def body := UTF8.encode(s, badBody)
        def headers := [
            "Connection" => "close",
            "Content-Length" => `${body.size()}`,
        ]
        return [200, headers, body]
    catch _:
        return null


object notFoundResource:
    to getStaticChildren():
        return [].asMap()

    to get(_):
        return notFoundResource

    to run(verb, headers):
        def [_, headers, body] := smallBody("Not found")
        return [404, headers, body]


def autoSI(var amount):
    if (amount < 1024):
        return `$amount `
    def prefixes := ["Ki", "Mi", "Gi", "Ti"]
    for prefix in prefixes:
        amount /= 1024
        if (amount < 1024):
            return `$amount $prefix`
    return `$amount ${prefixes[-1]}`


def makeDebugResource(runtime):
    return object debugResource:
        to getStaticChildren():
            return [].asMap()

        to get(_):
            return notFoundResource

        to run(_, headers):
            def heap := runtime.getHeapStatistics()
            def reactor := runtime.getReactorStatistics()

            def buckets := heap.getBuckets().sortValues().reverse().slice(0, 20)
            def bucketList := [for name => count in (buckets) tag.li(`$name: $count`)]
            def heapTag := tag.div(
                tag.h2("Heap"),
                tag.p(`Number of live objects: ${heap.getObjectCount()}`),
                tag.p(`Conservative heap size: ${autoSI(heap.getMemoryUsage())}B`),
                tag.p("Most common objects on the heap:"),
                M.call(tag, "ul", bucketList))
            def reactorTag := tag.div(
                tag.h2("Reactor"),
                tag.p(`Alarms: ${reactor.getAlarms()}`),
                tag.p(`Selectables: ${reactor.getSelectables()}`))
            def body := tag.body(tag.h1("Debug Info"), heapTag, reactorTag)
            return smallBody(`$body`)


def makeResource(worker, var children :Map[Str, Any]):
    return object resource:
        to getStaticChildren():
            return children

        to get(segment :Str):
            if (children.contains(segment)):
                return children[segment]
            return notFoundResource

        to put(segment :Str, child):
            children |= [segment => child]

        to run(verb, headers):
            return worker(resource, verb, headers)


def makeResourceApp(root):
    def resourceApp(request):
        escape badRequest:
            def [[verb, path], headers] exit badRequest := request
            def [==""] + segments exit badRequest := path.split("/")
            var resource := root
            for segment in segments.slice(0, segments.size() - 1):
                resource get= (segment)
            def final := segments[segments.size() - 1]
            if (final != ""):
                resource get= (final)
            return resource(verb, headers)
        catch _:
            return null
    return resourceApp


[
    => notFoundResource,
    => makeDebugResource,
    => makeResource,
    => makeResourceApp,
]
