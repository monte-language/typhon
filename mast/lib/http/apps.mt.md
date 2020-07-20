```
import "lib/http/headers" =~ [=> Headers, => emptyHeaders]
exports (addBaseOnto)
```

This is a small collection of useful HTTP applications. We provide strong
opinions and a roadmap for folks who want to write their own opinionated
scaffolding.

To raise Monte awareness, as well as to make it easier to deploy headers that
should be everywhere, we can pre-build a custom header map.

```
def theHeaders :DeepFrozen := emptyHeaders().with("spareHeaders" => [
    b`Server` => b`Monte (Typhon) (.i ma'a tarci pulce)`,
])
```

Some error responses are pre-built in order to encourage not giving ad-hoc
error messages to users. When giving an error response, we'd like to advise
the client that the connection should be closed.

```
def closeHeaders :DeepFrozen := theHeaders.with("spareHeaders" => [
    b`Connection` => b`close`,
] | theHeaders.spareHeaders())
```

We'll define some generic error conditions; 400 is a generic client error,
indicating a mistake on their end, while 500 is a generic server error,
indicating a problem internally.

```
def error400 :DeepFrozen := [
    "statusCode" => 400,
    "headers" => closeHeaders,
    "body" => b`Bad Request`,
]

def error500 :DeepFrozen := [
    "statusCode" => 500,
    "headers" => closeHeaders,
    "body" => b`Internal Server Error`,
]
```

We'll also need a 501, for indicating that a request went unhandled.

```
def error501 :DeepFrozen := [
    "statusCode" => 501,
    "headers" => closeHeaders,
    "body" => b`Not Implemented`,
]
```

Here is the first application. It always returns a response, so it should be
used as the basis for composing applications. It also does some helpful
things.

```
def addBaseOnto(app) as DeepFrozen:
    def baseApp(request):
        traceln(`baseApp($request)`)
        # null means a bad request that was unparseable.
        var res := if (request == null) {
            # We must close the connection after a bad request, since a parse
            # failure leaves the request tube in an indeterminate state.
            error400
        } else {
            try {
                app(request)
            } catch problem {
                traceln(`Exception in HTTP app $app:`)
                traceln.exception(problem)
                error500
            }
        }
        traceln(`res $res`)
        if (res == null) { res := error501 }
        def [=> statusCode, => headers, => body] := res
        def spares := headers.spareHeaders() | theHeaders.spareHeaders()
        def newHeaders := headers.with("spareHeaders" => spares)
        return [=> statusCode, "headers" => newHeaders, => body]
    return baseApp
```

This base is surprisingly resilient; consider how `addBaseOnto(traceln)` might
behave.
