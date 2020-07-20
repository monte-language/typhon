import "lib/codec/utf8" =~ [=> UTF8]
import "lib/http/tag" =~ [=> tag]
import "lib/http/server" =~ [=> makeHTTPEndpoint]
exports (smallBody,
         notFoundResource,
         makeDebugResource,
         makeResource,
         makeResourceApp,
         main)


def smallBody(s) as DeepFrozen:
    escape badBody:
        def body := UTF8.encode(s, badBody)
        def headers := [
            "Connection" => "close",
            "Content-Length" => `${body.size()}`,
        ]
        return ["statusCode" => 200, => headers, => body]
    catch _:
        return null


object notFoundResource as DeepFrozen:
    "
    A leaf resource which indicates that the actual requested resource was
    not found.

    This resource simply returns a 404 status code and a minimal error
    message.
    "

    to getStaticChildren():
        return [].asMap()

    to get(_):
        return notFoundResource

    to run(_request):
        def [=> headers, => body] | _ := smallBody("Not found")
        return ["statusCode" => 404, => headers, => body]


def autoSI(var amount) as DeepFrozen:
    if (amount < 1024):
        return `$amount `
    def prefixes := ["Ki", "Mi", "Gi", "Ti"]
    for prefix in (prefixes):
        amount /= 1024
        if (amount < 1024):
            return `$amount $prefix`
    return `$amount ${prefixes[-1]}`


def makeDebugResource(runtime) as DeepFrozen:
    return object debugResource:
        to getStaticChildren():
            return [].asMap()

        to get(_):
            return notFoundResource

        to run(request):
            def [=> headers, => body] | _ := request
            def requestTag := tag.div(
                tag.h2("Request"),
                tag.h3("Headers"),
                tag.p(`$headers`),
                tag.h3("Body"),
                tag.p(`$body`))

            def heap := runtime.getHeapStatistics()
            def reactor := runtime.getReactorStatistics()

            # We want to sort by the total footprint of each bucket.
            # Fortunately, the buckets already come as name => [totalSize,
            # count].
            def buckets := heap.getBuckets().sortValues().reverse().slice(0, 20)
            def bucketList := [for name => [totalSize, count] in (buckets)
                               tag.li(`$name: $count objects,
                                       ${totalSize // count} bytes each, total
                                       footprint ${autoSI(totalSize)}B`)]
            def heapTag := tag.div(
                tag.h2("Heap"),
                tag.p(`Number of live objects: ${heap.getObjectCount()}`),
                tag.p(`Conservative heap size: ${autoSI(heap.getMemoryUsage())}B`),
                tag.p("Most common objects on the heap:"),
                M.call(tag, "ul", bucketList))
            def reactorTag := tag.div(
                tag.h2("Reactor"),
                tag.p(`Handles: ${reactor.getHandles()}`))
            def body := tag.body(tag.h1("Debug Info"), requestTag, heapTag, reactorTag)
            return smallBody(`$body`)


def makeResource(worker, var children :Map[Str, Any]) as DeepFrozen:
    return object resource:
        to getStaticChildren():
            return children

        to get(segment :Str):
            if (children.contains(segment)):
                return children[segment]
            return notFoundResource

        to put(segment :Str, child):
            children |= [segment => child]

        to run(request):
            return worker(resource, request)


def makeResourceApp(root) as DeepFrozen:
    def resourceApp(request):
        traceln(`resourceApp $request`)
        escape badRequest:
            def [=> path] | _ exit badRequest := request
            def [==""] + segments exit badRequest := path.split("/")
            var resource := root
            for segment in (segments.slice(0, segments.size() - 1)):
                resource get= (segment)
            def final := segments[segments.size() - 1]
            if (final != ""):
                resource get= (final)
            return resource(request)
        catch _:
            def [=> headers, => body] | _ := smallBody("bad request?")
            return ["statusCode" => 400, => headers, => body]
    return resourceApp


def main(_argv, => currentRuntime, => makeTCP4ServerEndpoint) as DeepFrozen:
    # Just a single / that shows the debug page.
    def root := makeDebugResource(currentRuntime)

    def port :Int := 8080
    def endpoint := makeHTTPEndpoint(makeTCP4ServerEndpoint(port))
    def app := makeResourceApp(root)
    endpoint.listen(app)

    return 0
