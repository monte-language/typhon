```
import "unittest" =~ [=> unittest :Any]
import "lib/codec/utf8" =~ [=> UTF8]
import "lib/http/apps" =~ [=> Response, => addBaseOnto]
import "lib/http/headers" =~ [=> emptyHeaders]
import "lib/http/server" =~ [=> makeHTTPEndpoint]
exports (makeRegistry, textExposition, addMonitoringOnto, main)
```

Quotes are largely out-of-order; Monte requires that we declare names before
using them.

> This document covers what functionality and API Prometheus client libraries
> should offer, with the aim of consistency across libraries, making the easy use
> cases easy and avoiding offering functionality that may lead users down the
> wrong path.

This document is also literate Monte. Today we will be writing a Prometheus
client library as a single module. We will also be responding directly to the
upstream Prometheus documentation on how this library should be written.

> There are [10 languages already supported](/docs/instrumenting/clientlibs) at
> the time of writing, so we’ve gotten a good sense by now of how to write a
> client. These guidelines aim to help authors of new client libraries produce
> good libraries.

None of the supported languages are capability-safe. As we shall see, Monte
does not make it easy or possible to do some of the things that the authors of
Prometheus take for granted.

## Preamble

We will need a way to declare monotone names; we can do it with a custom slot.

```
def makeMonotoneSlot(v, guard :DeepFrozen) as DeepFrozen:
    var storage :guard := v
    return object monotoneSlot:
        to get():
            return storage
        to put(u :guard):
            if (v > u):
                throw(`Monotonicity failed: $v > $u`)
            storage := u
```

We will need to invoke `eval()` several times with the safe scope.

```
def safeEval(expr :DeepFrozen) as DeepFrozen:
    return eval(expr, safeScope)
```

We will need a basic primitive for handling the multidimensionality of labels
in a flexible way. This maker wraps a map from a canonical ordering of label
parameters to the raw counter/gauge/bucket storage, which in all cases will be
unwrapped values.

We will only use `Double` for values, because Prometheus uses double-precision
floating-point numbers for values. This is unfortunate because of the known
edge cases:

    ▲> def x := 9_007_199_254_740_992
    Result: 9007199254740992
    ▲> x + 1
    Result: 9007199254740993
    ▲> x + 1.0
    Result: 9007199254740992.000000

We'll also permit overriding the zero value, for gauges.

```
# XXX should we split the returned object whether `labels.isEmpty()`?
def makeLabelMap(namespace :Str, labels :List[Str],
                 => zero :Double := 0.0) as DeepFrozen:
    # XXX could use .diverge/2 when supported in Typhon
    def values := [].asMap().diverge()
```

It could be the case that we have no labels, in which case we must immediately
zero out the default bucket to prevent missing metrics.

```
    if (labels.isEmpty()):
        values[[]] := zero
```

This transformer takes a map of label names to label parameters, and returns
the parameters as a list. In doing so, we transform from what might be a
named-argument map, with Miranda keys, into precisely the parameters that
we'll have to pass around later.

```
    def trans(specimen, ej) :List:
        def m :Map exit ej := specimen
        return [for l in (labels) m.fetch(l, ej)]
    return object labelMap:
```

Collecting from a label map is essentially a pretty-printing operation.
Iterators of mutable maps are snapshotted automatically in Monte, mostly to
help avoid re-entrancy bugs.

```
        to collect():
            return if (labels.isEmpty()) {
                [namespace => values[[]]]
            } else {
                [for k => v in (values) {
                    def guts := ",".join([for k => v in (labels) `$k="$v"`])
                    `$namespace{$guts}`
                } => v]
            }
```

And these map operations include the zero-value cushion.

```
        to get(via (trans) params):
            return values.fetch(params, fn {
                values[params] := zero
            })
        to put(via (trans) params, v):
            values[params] := v
```

If a user fixes the label parameters, then they can get the Monte equivalent
of `&labelMap[labels]`, a slot that can be addressed as a proxy for the value.

```
        to child(via (trans) params):
            return object childLabelSlot:
                to get():
                    return values.fetch(params, fn {
                        values[params] := zero
                    })
                to put(v):
                    values[params] := v
```

> ## Conventions
> 
> MUST/MUST NOT/SHOULD/SHOULD NOT/MAY have the meanings given in
> [https://www.ietf.org/rfc/rfc2119.txt](https://www.ietf.org/rfc/rfc2119.txt)
> 
> In addition ENCOURAGED means that a feature is desirable for a library to have,
> but it’s okay if it’s not present. In other words, a nice to have.

Total number of "MUST" instances ignored in this revision: 4

This seems like a good time to show how Monte handles assertions like "MUST
check that v >= 0". We can create custom guards which perform this check for
us.

```
def PosDouble :DeepFrozen := Double >= 0.0
```

A sadness of IEEE 754 is that this guard will admit `-0.0`, `NaN`, and
`Infinity`. Such is life.

> Things to keep in mind:
> 
> * Take advantage of each language’s features.

What are the features of Monte which are good for writing Prometheus clients?

 * Compact, assertive code

 * Built-in asynchronous primitives

> * The common use cases should be easy.

Many of them will be impossible.

> * The correct way to do something should be the easy way.

The incorrect ways, again, should be impossible.

> * More complex use cases should be possible.

You can do anything you like.

> The common use cases are (in order):
> 
> * Counters without labels spread liberally around libraries/applications.

Sure. This will be a pattern that we want to encourage.

> * Timing functions/blocks of code in Summaries/Histograms.

Timing anything smaller than a vat turn is tricky.

> * Gauges to track current states of things (and their limits).

Sure.

> * Monitoring of batch jobs.

This is the use case that will suffer the most. Monte frowns on
throughput-focused APIs which do not have strong compatibility and play with
one-at-a-time APIs.

> ## Overall structure

> Client libraries SHOULD follow function/method/class names mentioned in this
> document, keeping in mind the naming conventions of the language they’re
> working in.

> Libraries MUST NOT offer functions/methods/classes with the same or similar
> names to ones given here, but with different semantics.

Or, in other words, this library may only offer one API and it must have the
same semantics as in other client libraries. No worries.

> For non-OO languages such as C, client libraries should follow the spirit of
> this structure as much as is practical.

Unfortunately, it is extremely common for folks to believe that
"object-oriented" languages all have classes, inheritance, members, etc. We
will have to discard many recommendations that might be Pythonic because they
are not in the spirit of Monte.

> Client libraries MUST be thread safe.

Monte does not have threads, so this is trivial.

> Clients MUST be written to be callback based internally. Clients SHOULD
> generally follow the structure described here.

Monte is already callback-based internally; it is not possible to write code
any other way. As for the rest of the structure, we shall try our best to
adapt it to Monte's idioms.

> The key class is the Collector. This has a method (typically called ‘collect’)
> that returns zero or more metrics and their samples. Collectors get registered
> with a CollectorRegistry. Data is exposed by passing a CollectorRegistry to a
> class/method/function "bridge", which returns the metrics in a format
> Prometheus supports. Every time the CollectorRegistry is scraped it must
> callback to each of the Collectors’ collect method.

Monte does not have classes. Instead, we have *makers*, functions which return
parameterized object literals.

We can have collector registries. In fact, we shall make registries our key
objects.

```
def makeRegistry(registryName :Str) as DeepFrozen:
    def collectors := [].asMap().diverge()

    return object registry:
```

> CollectorRegistry SHOULD offer `register()`/`unregister()` functions, and a
> Collector SHOULD be allowed to be registered to multiple CollectorRegistrys.

We politely decline. Instead, users should feel empowered to create private
registries.

> More advanced uses cases (such as proxying from another
> monitoring/instrumentation system) require writing a custom Collector. Someone
> may also want to write a "bridge" that takes a CollectorRegistry and produces
> data in a format a different monitoring/instrumentation system understands,
> allowing users to only have to think about one instrumentation system.

This suggests that the registry should have some sort of canonical export for
its collection. We will use standard Monte maps.

```
        to collect() :Map:
            def rv := [].asMap().diverge()
            for collector in (collectors):
                for k => v in (collector()):
                    rv[k] := v
            return rv.snapshot()
```

> The interface most users interact with are the Counter, Gauge, Summary, and
> Histogram Collectors. These represent a single metric, and should cover the
> vast majority of use cases where a user is instrumenting their own code.

Sure. We define these collectors below, to line up with this document.

> Counter and Gauge MUST be part of the client library. At least one of Summary
> and Histogram MUST be offered.

We present Counters and Gauges. I'll do the others later.

> These should be primarily used as file-static variables, that is, global
> variables defined in the same file as the code they’re instrumenting. The
> client library SHOULD enable this. The common use case is instrumenting a piece
> of code overall, not a piece of code in the context of one instance of an
> object. Users shouldn’t have to worry about plumbing their metrics throughout
> their code, the client library should do that for them (and if it doesn’t,
> users will write a wrapper around the library to make it "easier" - which
> rarely tends to go well).

Monte does not have "file-static variables" or "global variables" with
mutation. Collectors must internally mutate. Therefore, Monte cannot have a
client library which does what is desired.

In Monte, all values need to be carefully plumbed through code. Collectors do
not get magic or special treatment, because Monte is not capable of giving
magic or special treatment.

Users cannot write wrappers which break the rules of Monte. I agree that
trying to write such a wrapper will not go well.

> Exactly how the metrics should be created varies by language. For some (Java,
> Go) a builder approach is best, whereas for others (Python) function arguments
> are rich enough to do it in one call.

We will do a single method call per metric.

> ### Counter
> 
> [Counter](/docs/concepts/metric_types/#counter) is a monotonically increasing
> counter.

A registry will not permit the same metric name to be registered twice. We can
enforce this with a *such-that* pattern. Read as, "name is a string, such that
collectors does not contain name":

```
        to counter(name :Str ? (!collectors.contains(name)),
```

> Gauge/Counter/Summary/Histogram MUST require metric descriptions/help to be
> provided.

Really? Have you *ever* experienced satisfaction and grokking of a metric
merely by reading its help string? But fine. I understand that there's a
cultural expectation around help strings.

In order to make the help string required, we ask for it positionally.

```
                   help :Str,
```

> While labels are powerful, the majority of metrics will not have labels.
> Accordingly the API should allow for labels but not dominate it.

Labels are ultimately optional, and we'll do some nice things for users who
don't pass them in order to simplify the API.

```
                   => labels :List[Str] := []):
```

> Counters MUST start at 0.

Our label maps already have zero-valued behavior from earlier.

```
            def labelMap := makeLabelMap(`${registryName}_$name`, labels)
```

This map will be collected by the registry. This not-quite-call, with a verb
but no parentheses, is a *verb curry*; calling m`collectors[name]()` is like
calling m`labelMap.collect()`, but the curried object isn't available through
the curry wrapper.

```
            collectors[name] := labelMap.collect
```

Let's build the counter object.

```
            object counter:
                to help() :Str:
                    return help
```

> It MUST NOT allow the value to decrease, however it MAY be reset to 0 (such
> as by server restart).

We can observe this by construction; the `dec` and `set` methods aren't
provided here.

> A counter MUST have the following methods:
> 
> * `inc()`: Increment the counter by 1

This is one of the great sadnesses of the Prometheus API: we would like to
have `Int`-valued counters, but it is impractical.

```
                to inc(params :Map[Str, Str]):
                    labelMap[params] += 1.0
```

> * `inc(double v)`: Increment the counter by the given amount. MUST check that v >= 0.

```
                to inc(params :Map[Str, Str], v :PosDouble):
                    labelMap[params] += v
```

> The general way to provide access to labeled dimension of a metric is via a
> `labels()` method that takes either a list of the label values or a map from
> label name to label value and returns a "Child". The usual
> `.inc()`/`.dec()`/`.observe()` etc. methods can then be called on the Child.

```
                to labels(params :Map[Str, Str]):
                    def &val := labelMap.child(params)
                    return object childCounter extends &val:
                        to inc():
                            val += 1.0
                        to inc(v :PosDouble):
                            val += v
```

Another problem which manifests here for the first (and not the last) time is
that the given signatures will require either multimethods or matchers.
Multimethods work in Monte but are contentious.

> There SHOULD be a way to initialize a given Child with the default value,
> usually just calling `labels()`. Metrics without labels MUST always be
> initialized to avoid [problems with missing
> metrics](/docs/practices/instrumentation/#avoid-missing-metrics).

These passages mean that if a user creates a metric without labels, then the
user should not have to pass an empty map repeatedly.

```
            return if (labels.isEmpty()) {
                counter.labels([].asMap())
            } else { counter }
```

> A counter is ENCOURAGED to have:
> 
> A way to count exceptions throw/raised in a given piece of code, and optionally
> only certain types of exceptions. This is count_exceptions in Python.

Maybe. I'll have to think on the API.

> ### Gauge
> 
> [Gauge](/docs/concepts/metric_types/#gauge) represents a value that can go up
> and down.

A gauge is like a counter, but with more methods and without the requirement
that the value is monotonically increasing.

```
        to gauge(name :Str ? (!collectors.contains(name)), help :Str,
                 => labels :List[Str] := [],
```

> Gauges MUST start at 0, you MAY offer a way for a given gauge to start at a
> different number.

We'll offer a named argument.

```
                 => zero :Double := 0.0):
            def labelMap := makeLabelMap(`${registryName}_$name`, labels, => zero)
            collectors[name] := labelMap.collect
            object gauge:
                to help() :Str:
                    return help
```

> A gauge MUST have the following methods:
> 
> * `inc()`: Increment the gauge by 1
> * `inc(double v)`: Increment the gauge by the given amount
> * `dec()`: Decrement the gauge by 1
> * `dec(double v)`: Decrement the gauge by the given amount
> * `set(double v)`: Set the gauge to the given value

```
                to inc(params :Map[Str, Str]):
                    labelMap[params] += 1.0
                to inc(params :Map[Str, Str], v :Double):
                    labelMap[params] += v
                to dec(params :Map[Str, Str]):
                    labelMap[params] -= 1.0
                to dec(params :Map[Str, Str], v :Double):
                    labelMap[params] -= v
                to set(params :Map[Str, Str], v :Double):
                    labelMap[params] := v
                to labels(params :Map[Str, Str]):
                    def &val := labelMap.child(params)
                    return object childCounter extends &val:
                        to inc():
                            val += 1.0
                        to inc(v :Double):
                            val += v
                        to dec():
                            val -= 1.0
                        to dec(v :Double):
                            val -= v
                        to set(v :Double):
                            val := v
            return if (labels.isEmpty()) {
                gauge.labels([].asMap())
            } else { gauge }
```

> A gauge SHOULD have the following methods:
> 
> * `set_to_current_time()`: Set the gauge to the current unixtime in seconds.

And the first "SHOULD" that must be ignored has arrived. In Monte, the system
timer is closely-held in the unsafe scope, which means that ordinary
user-level code cannot get at it.

> A gauge is ENCOURAGED to have:
> 
> A way to track in-progress requests in some piece of code/function. This is
> `track_inprogress` in Python.

Maybe. Interesting desire.

> A way to time a piece of code and set the gauge to its duration in seconds.
> This is useful for batch jobs. This is startTimer/setDuration in Java and the
> `time()` decorator/context manager in Python. This SHOULD match the pattern in
> Summary/Histogram (though `set()` rather than `observe()`).

I might just repeat, "Timers are privileged in Monte," each time.

> ### Summary
> 
> A [summary](/docs/concepts/metric_types/#summary) samples observations (usually
> things like request durations) over sliding windows of time and provides
> instantaneous insight into their distributions, frequencies, and sums.
> 
> A summary MUST NOT allow the user to set "quantile" as a label name, as this is
> used internally to designate summary quantiles. A summary is ENCOURAGED to
> offer quantiles as exports, though these can’t be aggregated and tend to be
> slow. A summary MUST allow not having quantiles, as just `_count`/`_sum` is
> quite useful and this MUST be the default.
> 
> A summary MUST have the following methods:
> 
> * `observe(double v)`: Observe the given amount
> 
> A summary SHOULD have the following methods:
> 
> Some way to time code for users in seconds. In Python this is the `time()`
> decorator/context manager. In Java this is startTimer/observeDuration. Units
> other than seconds MUST NOT be offered (if a user wants something else, they
> can do it by hand). This should follow the same pattern as Gauge/Histogram.
> 
> Summary `_count`/`_sum` MUST start at 0.
> 
> ### Histogram
> 
> [Histograms](/docs/concepts/metric_types/#histogram) allow aggregatable
> distributions of events, such as request latencies. This is at its core a
> counter per bucket.
> 
> A histogram MUST NOT allow `le` as a user-set label, as `le` is used internally
> to designate buckets.
> 
> A histogram MUST offer a way to manually choose the buckets. Ways to set
> buckets in a `linear(start, width, count)` and `exponential(start, factor,
> count)` fashion SHOULD be offered. Count MUST exclude the `+Inf` bucket.
> 
> A histogram SHOULD have the same default buckets as other client libraries.
> Buckets MUST NOT be changeable once the metric is created.
> 
> A histogram MUST have the following methods:
> 
> * `observe(double v)`: Observe the given amount
> 
> A histogram SHOULD have the following methods:
> 
> Some way to time code for users in seconds. In Python this is the `time()`
> decorator/context manager. In Java this is `startTimer`/`observeDuration`.
> Units other than seconds MUST NOT be offered (if a user wants something else,
> they can do it by hand). This should follow the same pattern as Gauge/Summary.
> 
> Histogram  `_count`/`_sum` and the buckets MUST start at 0.
> 
> **Further metrics considerations**
> 
> Providing additional functionality in metrics beyond what’s documented above as
> makes sense for a given language is ENCOURAGED.
> 
> If there’s a common use case you can make simpler then go for it, as long as it
> won’t encourage undesirable behaviours (such as suboptimal metric/label
> layouts, or doing computation in the client).
> 
> ### Labels
> 
> Labels are one of the [most powerful
> aspects](/docs/practices/instrumentation/#use-labels) of Prometheus, but
> [easily abused](/docs/practices/instrumentation/#do-not-overuse-labels).
> Accordingly client libraries must be very careful in how labels are offered to
> users.

This document has some surprising priorities. Preventing users from sending
spurious labels is important, but avoiding global mutable state is not.
Interesting.

> Client libraries MUST NOT under any circumstances allow users to have different
> label names for the same metric for Gauge/Counter/Summary/Histogram or any
> other Collector offered by the library.

Under *any* circumstances? That's a big request! We can do it per-registry,
but this probably counts as a disobeyed "MUST".

> Metrics from custom collectors should almost always have consistent label
> names. As there are still rare but valid use cases where this is not the case,
> client libraries should not verify this.

This, too, sounds more like word salad. What is a "consistent label name" and
why should I care?

> A client library MUST allow for optionally specifying a list of label names at
> Gauge/Counter/Summary/Histogram creation time. A client library SHOULD support
> any number of label names. A client library MUST validate that label names meet
> the [documented
> requirements](/docs/concepts/data_model/#metric-names-and-labels).

We shall encourage correctly-formed label names by using keyword arguments.

> The Child returned by `labels()` SHOULD be cacheable by the user, to avoid
> having to look it up again - this matters in latency-critical code.

The word "cacheable" is a trap here. Yes, children of collectors should
themselves be collectors, and users should feel free to closely-hold
collectors.

> Metrics with labels SHOULD support a `remove()` method with the same signature
> as `labels()` that will remove a Child from the metric no longer exporting it,
> and a `clear()` method that removes all Children from the metric. These
> invalidate caching of Children.

And the trap is sprung. Build a cache and then worry about cache invalidation?
No thanks.

> ### Metric names
> 
> Metric names must follow the
> [specification](/docs/concepts/data_model/#metric-names-and-labels). As with
> label names, this MUST be met for uses of Gauge/Counter/Summary/Histogram and
> in any other Collector offered with the library.

Sure.

> Many client libraries offer setting the name in three parts:
> `namespace_subsystem_name` of which only the `name` is mandatory.

We can infer a name from the FQN (Fully-Qualified Name) of a module, but
modules do not directly maintain their own names, so it is possible for FQNs
to not be legal Prometheus identifiers. In particular, Monte FQNs usually have
characters like `$` in them.

We can instead require registries to provide the top parts of this triple.

> Dynamic/generated metric names or subparts of metric names MUST be discouraged,
> except when a custom Collector is proxying from other
> instrumentation/monitoring systems. Generated/dynamic metric names are a sign
> that you should be using labels instead.

How? This counts as a failed "MUST".

> ### Metric description and help

> Any custom Collectors provided with the client libraries MUST have
> descriptions/help on their metrics.

Sure.

> It is suggested to make it a mandatory argument, but not to check that it’s of
> a certain length as if someone really doesn’t want to write docs we’re not
> going to convince them otherwise. Collectors offered with the library (and
> indeed everywhere we can within the ecosystem) SHOULD have good metric
> descriptions, to lead by example.

Okay, so the idea is that, since help strings have been nigh-useless in the
past, they could be more useful in the future, if we all work together and
establish some cultural expectations.

> ## Standard and runtime collectors
> 
> Client libraries SHOULD offer what they can of the Standard exports, documented
> below.
> 
> These SHOULD be implemented as custom Collectors, and registered by default on
> the default CollectorRegistry. There SHOULD be a way to disable these, as there
> are some very niche use cases where they get in the way.

The desired metrics are extremely unsafe, and not part of standard Monte. We
can export some of them if we are given the requisite unsafe objects.

> ### Process metrics
> 
> These exports should have the prefix `process_`. If a language or runtime
> doesn't expose one of the variables it'd just not export it. All memory values
> in bytes, all times in unixtime/seconds.
> 
> | Metric name                        | Help string                                            | Unit             |
> | ---------------------------------- | ------------------------------------------------------ | ---------------  |
> | `process_cpu_seconds_total`        | Total user and system CPU time spent in seconds.       | seconds          |
> | `process_open_fds`                 | Number of open file descriptors.                       | file descriptors |
> | `process_max_fds`                  | Maximum number of open file descriptors.               | file descriptors |
> | `process_virtual_memory_bytes`     | Virtual memory size in bytes.                          | bytes            |
> | `process_virtual_memory_max_bytes` | Maximum amount of virtual memory available in bytes.   | bytes            |
> | `process_resident_memory_bytes`    | Resident memory size in bytes.                         | bytes            |
> | `process_heap_bytes`               | Process heap size in bytes.                            | bytes            |
> | `process_start_time_seconds`       | Start time of the process since unix epoch in seconds. | seconds          |

Note how the help strings are specified just as precisely and exactly as the
metric names.

We can, if given `currentRuntime`, ask for Typhon-specific heap information.

```
        to processMetrics(currentRuntime):
            def processMetrics():
                def heap := currentRuntime.getHeapStatistics()
                return [
                    "process_heap_bytes" => heap.getMemoryUsage().asDouble(),
                ]
            collectors["process"] := processMetrics
```

> ### Runtime metrics
> 
> In addition, client libraries are ENCOURAGED to also offer whatever makes sense
> in terms of metrics for their language’s runtime (e.g. garbage collection
> stats), with an appropriate prefix such as `go_`, `hostspot_` etc.

We should export vat information from the runtime.

> ## Exposition
>
> Clients MUST implement the text-based exposition format outlined in the
> [exposition formats](/docs/instrumenting/exposition_formats) documentation.

We cheat heavily here, since we don't intend to implement any other exposition
formats for a very long time, and have HELP and TYPE prepacked by
`registry.collect()`. As a result, the actual exposition is quite brief.

```
def textExposition(registry) :Bytes as DeepFrozen:
    def lines := [for k => v in (registry.collect()) `$k $v$\n`]
    return UTF8.encode("".join(lines), null)
```

We also can provide a basic bit of middleware which adds the scrape endpoints
onto an application. After a bit of fussing with the application API, the best
composition seems to be for users to build and pass in their own registry.

```
def addMonitoringOnto(app, registry) as DeepFrozen:
    "
    Add Prometheus-compatible scrape endpoints onto `app`, collecting from
    `registry`.
    "

    return def promMonitoringWrapperApp(req):
        return switch (req.path()):
            match =="/healthz":
                Response.full("statusCode" => 200, "headers" => emptyHeaders(),
                              "body" => b`je'e`)
            match =="/metrics":
                def body := textExposition(registry)
                Response.full("statusCode" => 200, "headers" => emptyHeaders(),
                              => body)
            match _:
                app(req)
```

> Reproducible order of the exposed metrics is ENCOURAGED (especially for human
> readable formats) if it can be implemented without a significant resource cost.

Monte gives this property nearly for free; we must only avoid techniques like
sorting.

> ## Unit tests
> 
> Client libraries SHOULD have unit tests covering the core instrumentation
> library and exposition.

Sure. Let's do a basic sanity test:

```
def testCounter(assert):
    def r := makeRegistry("test")
    def c := r.counter("tests", "This help string will never be seen.")
    assert.equal(r.collect(), ["test_tests" => 0.0])
    c.inc()
    assert.equal(r.collect(), ["test_tests" => 1.0])
```

And we'll take gauges for a test drive too:

```
def testGauge(assert):
    def r := makeRegistry("test")
    def g := r.gauge("tests", "This help string will never be seen.")
    # Doubles are exact on this integer range, so these operations should be
    # trivially exact.
    assert.equal(r.collect(), ["test_tests" => 0.0])
    g.inc()
    assert.equal(r.collect(), ["test_tests" => 1.0])
    g.inc(2.0)
    assert.equal(r.collect(), ["test_tests" => 3.0])
    g.dec()
    assert.equal(r.collect(), ["test_tests" => 2.0])
    g.dec(3.0)
    assert.equal(r.collect(), ["test_tests" => -1.0])
    # Nontrivial FP exactness. We can rely on this due to passthrough; .set/1
    # is effectively an algebraic action.
    g.set(5.7)
    assert.equal(r.collect(), ["test_tests" => 5.7])
```

And make sure labels work:

```
def testCounterLabels(assert):
    def labels := ["t"]
    def r := makeRegistry("test")
    def c := r.counter("tests", "Silent help.", => labels)
    c.inc(["t" => "200"])
    def child := c.labels(["t" => "400"])
    child.inc(2.0)
    assert.equal(r.collect().sortKeys(), [
        `test_tests{t="200"}` => 1.0,
        `test_tests{t="400"}` => 2.0,
    ])
```

And register the tests.

```
unittest([
    testCounter,
    testCounterLabels,
    testGauge,
])
```

> Client libraries are ENCOURAGED to offer ways that make it easy for users to
> unit-test their use of the instrumentation code. For example, the
> `CollectorRegistry.get_sample_value` in Python.

Due to the confinement properties of Monte, along with the lack of global
mutable state, it should be trivial for any user to replace registries for
testing.

> ## Packaging and dependencies
> 
> Ideally, a client library can be included in any application to add some
> instrumentation without breaking the application.

In reality, plan interference is a real hazard any time we interleave plans.
Additionally, the act of observation is non-neutral and will have a definite
impact on the behavior of the application.

> Accordingly, caution is advised when adding dependencies to the client library.
> For example, if you add a library that uses a Prometheus client that requires
> version x.y of a library but the application uses x.z elsewhere, will that have
> an adverse impact on the application?

Monte has a much better per-module compilation story than its peers.
Additionally, this module has very few dependencies.

> It is suggested that where this may arise, that the core instrumentation is
> separated from the bridges/exposition of metrics in a given format. For
> example, the Java simpleclient `simpleclient` module has no dependencies, and
> the `simpleclient_servlet` has the HTTP bits.

It is 2018, so Monte has HTTP tools in the standard library. We can define a
basic entrypoint to show off usage.

```
def main(_argv, => currentRuntime, => makeTCP4ServerEndpoint) as DeepFrozen:
    def registry := makeRegistry("demo")
    registry.processMetrics(currentRuntime)
    def app := addMonitoringOnto(addBaseOnto(traceln), registry)

    def port :Int := 8080
    def endpoint := makeHTTPEndpoint(makeTCP4ServerEndpoint(port))
    endpoint.listen(app)

    return 0
```

> ## Performance considerations
> 
> As client libraries must be thread-safe, some form of concurrency control is
> required and consideration must be given to performance on multi-core machines
> and applications.

Sure. However, it is not possible to contend on writes or reads in Monte when
running synchronous code.

> In our experience the least performant is mutexes.
> 
> Processor atomic instructions tend to be in the middle, and generally
> acceptable.
> 
> Approaches that avoid different CPUs mutating the same bit of RAM work best,
> such as the DoubleAdder in Java’s simpleclient. There is a memory cost though.
> 
> As noted above, the result of `labels()` should be cacheable. The concurrent
> maps that tend to back metric with labels tend to be relatively slow.
> Special-casing metrics without labels to avoid `labels()`-like lookups can help
> a lot.

Doing caching of children like this is rather insane as long as collectors do
not belong to single registries. On a related note, we cannot begin to
implement this sort of cache without something like `WeakMap`.

> Metrics SHOULD avoid blocking when they are being incremented/decremented/set
> etc. as it’s undesirable for the whole application to be held up while a scrape
> is ongoing.

Oh, okay. In Monte, we can always avoid blocking. Imagine that some operation
`f.run()` is expensive. We can replace it with `f<-run()`, giving a promise
and avoiding blocking. We therefore "SHOULD" design this module to be used via
sends. A user may wish to write something like:

    def handleRequest(req):
        requestsReceived<-inc()
        when (def rv := process(req)) ->
            requestsHandled<-inc()
            rv
        

The downside is that a scrape may not read the most-recently-written value,
but a scrape will at least, by synchronously calling `.collect()` instead of
`<-collect()`, read a fully-consistent snapshot of the system state.

> Having benchmarks of the main instrumentation operations, including labels, is
> ENCOURAGED.

What is this, Go?

> Resource consumption, particularly RAM, should be kept in mind when performing
> exposition. Consider reducing the memory footprint by streaming results, and
> potentially having a limit on the number of concurrent scrapes.

Monitoring is not free.
