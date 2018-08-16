```
import "lib/gadts" =~ [=> makeGADT]
import "lib/http/headers" =~ [=> Headers, => emptyHeaders]
exports (Response)
```

First, we need to define what a response is. Historically, a response has
consisted of a status code, some headers, and a body.

In the future, we'll support streaming bodies in a separate constructor.

```
def Response :DeepFrozen := makeGADT("Response", [
    "full" => [
        "statusCode" => Int,
        # "headers" => Headers,
        "headers" => DeepFrozen,
        "body" => Bytes,
    ],
])
```
