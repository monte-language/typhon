exports (timeit)

# A benchmarking algorithm strongly inspired by Python's timeit module.

def timeit(f, measureTimeTaken) :Vow[Double] as DeepFrozen:
    "
    Run `f` many times, returning the amount of time that `f` typically takes.

    `measureTimeTaken` could be e.g. `Timer<-measureTimeTaken`.

    After approximating how long `f` takes on its own, we run it many times in
    a loop, in order to estimate how underlying platform state may respond to
    `f` becoming a hot code path.
    "

    # N.B. Timer<-measureTimeTaken/1 returns a pair [rv, timeTaken :Double].
    # But we don't really care about the result value, just the time taken;
    # Monte Carlo algorithms are just as valid as Las Vegas algorithms here.

    var loops := 1
    var timeTaken := 0.0
    def bench():
        for _ in (0..!loops) { f() }

    # How many loops should we take in each trial?
    def autorange():
        return if (timeTaken >= 0.2) { timeTaken / loops } else {
            when (def rv := measureTimeTaken(bench)) -> {
                timeTaken := rv[1]
                # CPython grows faster: 1, 2, 5, 10, 20, 50, …
                loops <<= 1
                autorange()
            }
        }

    # Take some trials.
    var loopsTaken := 0
    def repeat():
        return if (loopsTaken >= 5) { timeTaken / loops } else {
            when (def candidate := measureTimeTaken(bench)) -> {
                loopsTaken += 1
                # CPython suggests that we take the minimum.
                timeTaken min= (candidate[1])
                repeat()
            }
        }

    return when (autorange()) ->
        when (repeat()) ->
            timeTaken / loops
