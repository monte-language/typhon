import "lib/streams" =~ [=> collectBytes]
import "lib/which" =~ [=> makePathSearcher, => makeWhich]
exports (getURL, main)

def getURL(curl, url :Bytes) as DeepFrozen:
    "Invoke cURL to retrieve `url`."

    def p := curl<-([url], [].asMap(), "stdout" => true)
    return collectBytes(p<-stdout())

def main(_argv, => currentProcess, => makeFileResource, => makeProcess) as DeepFrozen:
    def paths := currentProcess.getEnvironment()[b`PATH`]
    def searcher := makePathSearcher(makeFileResource, paths)
    def which := makeWhich(makeProcess, searcher)
    def curl := which("curl")
    def bs := getURL(curl, b`https://example.com/`)
    return when (curl, bs) ->
        traceln(`Got cURL: $curl`)
        traceln(`Got ${bs.size()} bytes, starts with: ${bs.slice(0, 10)}`)
        0
