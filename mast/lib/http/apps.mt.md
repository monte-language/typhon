```
import "lib/http/headers" =~ ["ASTBuilder" => headerBuilder]
exports (addBaseOnto)
```

This is a small collection of useful HTTP applications. We provide strong
opinions and a roadmap for folks who want to write their own opinionated
scaffolding.

Some error responses are pre-built in order to encourage not giving ad-hoc
error messages to users. When giving an error response, we'd like to advise
the client that the connection should be closed.

```
def closeHeaders :DeepFrozen := headerBuilder.ResponseHeaders(
    "contentType" => null,
    "connection" => headerBuilder.Close(),
    "transferEncoding" => [],
    "spareHeaders" => [],
)
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
things regarding error handling.

```
def addBaseOnto(app) as DeepFrozen:
    def baseApp(request):
        traceln(`baseApp($request)`)
        # null means a bad request that was unparseable.
        return if (request == null) {
            # We must close the connection after a bad request, since a parse
            # failure leaves the request tube in an indeterminate state.
            error400
        } else {
            try {
                def rv := app(request)
                traceln(`response $rv`)
                (rv == null).pick(error501, rv)
            } catch problem {
                traceln(`Exception in HTTP app $app:`)
                traceln.exception(problem)
                error500
            }
        }
    return baseApp
```

This base is surprisingly resilient; consider how `addBaseOnto(traceln)` might
behave.
