This is a runnable tool.

```
import "lib/codec/utf8" =~ [=> UTF8]
import "lib/http/apps" =~ [=> addBaseOnto]
import "lib/http/headers" =~ [=> emptyHeaders]
import "lib/http/server" =~ [=> makeHTTPEndpoint]
import "lib/prom" =~ [=> addMonitoringOnto, => makeRegistry]
exports (main)
```

Today we shall provide a harness for
[kubeless](https://github.com/kubeless/kubeless).

```
def makeKubelessApp(handler) as DeepFrozen:
    return def kubelessApp(request):
        def [=> headers, => body] | _ := request
        def [
            => ::"event-id" := null,
            => ::"event-namespace" := null,
            => ::"event-time" := null,
            => ::"event-type" := null,
        ] | _ := headers.spareHeaders()
        def event := [
            "data" => body,
            => ::"event-id",
            => ::"event-namespace",
            => ::"event-time",
            => ::"event-type",
        ]
        def context := [].asMap()
        return try {
            def rv := handler(event, context)
            if (rv =~ body :Bytes) {
                ["statusCode" => 200, "headers" => emptyHeaders(), => body]
            } else { rv }
        } catch problem {
            traceln.exception(problem)
            null
        }
```

Everything is passed via environment variables, rather than as positional
arguments.

```
def main(_argv, => currentProcess, => currentRuntime,
         => makeFileResource, => makeTCP4ServerEndpoint) as DeepFrozen:
    def [
```

>  - The file to load can be specified using an environment variable `MOD_NAME`.

```
        (b`MOD_NAME`) => via (UTF8.decode) modulePath,
```

>  - The function to load can be specified using an environment variable `FUNC_HANDLER`.

```
        (b`FUNC_HANDLER`) => via (UTF8.decode) exportName,
```

>  - The port used to expose the service can be modified using an environment variable `FUNC_PORT`.

Clients seem to use 8080 as a default port.

```
        (b`FUNC_PORT`) => via (_makeInt.fromBytes) serverPort :Int := 8080,
```

And that's all we need from the environment.

```
    ] | _ := currentProcess.getEnvironment()
```

Set up a Prometheus registry. By doing this early, we can let the handler have
access to the registry too.

```
    def registry := makeRegistry("function")
    registry.processMetrics(currentRuntime)
```

Load the target module. We require the module to be a "muffin"; that is, it
should have no imports. It should also be in MAST format.

```
    return when (def bs := makeFileResource(modulePath)<-getContents()) ->
        def expr := readMAST(bs)
```

Evaluate the target module and retrieve the event handler.

```
        def handler := eval(expr, safeScope)(null)[exportName]
```

Set up the application itself.

```
        var app := makeKubelessApp(handler)
```

>  - Exceptions in the function should be caught. The server should not exit due to a function error.

```
        app := addBaseOnto(app)
```

>  - The server should return `200 - OK` to requests at `/healthz`.

```
        app := addMonitoringOnto(app, registry)
```

Set up the server and start listening.

```
        def endpoint := makeHTTPEndpoint(makeTCP4ServerEndpoint(serverPort))
        endpoint.listen(app)
```

And finally "return" successfully. We won't actually reach this point in
normal operation.

```
        0
```

Here are some features we don't have:

>  - Functions should receive two parameters: `event` and `context` and should return the value that will be used as HTTP response. See [the functions standard signature](/docs/runtimes#runtimes-interface) for more information. The information that will be available in `event` parameter will be received as HTTP headers.
>  - Requests should be served in parallel.
>  - Functions should run `FUNC_TIMEOUT` as maximum. If, due to language limitations, it is not possible not stop the user function, at least a `408 - Timeout` response should be returned to the HTTP request.
>  - Requests should be logged to stdout including date, HTTP method, requested path and status code of the response.
>  - The function should expose Prometheus statistics in the path `/metrics`. At least it should expose:
>    - Calls per HTTP method
>    - Errors per HTTP method
>    - Histogram with the execution time per HTTP method
