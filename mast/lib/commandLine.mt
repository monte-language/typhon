import "lib/wrappers" =~ [=> makeRevokable]
exports (makePrompt)

def makePrompt(stdio) as DeepFrozen:
    "
    A basic CLI toolkit on `stdio`.

    Makes a pair of a prompt and a cleanup runnable.
    "

    def stdin := stdio.stdin()
    def stdout := stdio.stdout()
    var enabled :Bool := true
    var lastLineSize :Int := 0
    var lineBuffer :Bytes := b``
    def whenDone

    def cleanup():
        if (lastLineSize > 0):
            stdout<-(b`$\n`)
        return when (stdout<-complete()) ->
            enabled := false
            bind whenDone := null

    # Internal only.
    def prepareLine(bs :Bytes) :Bytes:
        def newLineSize := bs.size()
        def padding := b` ` * (lastLineSize - newLineSize).max(0)
        lastLineSize := newLineSize
        return bs + padding

    object prompt:
        to whenDone():
            "A promise which resolves when the prompt is closed down."

            return whenDone

        to writeLine(bs :Bytes):
            "Write `bs` and start a new line."

            return stdout<-(prepareLine(bs) + b`$\n`)

        to setLine(bs :Bytes):
            "
            Change the current line to `bs`.

            It is implied that this change is temporary and that a
            `.writeLine` will come later to set the current line permanently.
            "

            return stdout<-(prepareLine(bs) + b`$\r`)

        to readLine() :Vow[Bytes]:
            "Read a line of `Bytes`."

            def rv
            stdin<-(object filler {
                to run(b) {
                    lineBuffer += b
                    bind rv := if (lineBuffer =~ b`@line$\n@rest`) {
                        lineBuffer := rest
                        bind rv := line
                    } else { stdin<-(filler) }
                }
                to complete() { cleanup() }
                to abort(problem) {
                    def message := `Problem reading from stdin: $problem`
                    when (prompt<-writeLine(message)) -> { cleanup() }
                }
            })
            return rv

        to ask(query :Bytes) :Vow[Bytes]:
            "Prompt the user with `query`."

            # Bug: While we are waiting for the user's reply, we do not
            # account for redrawing `query` when setting the line. Shouldn't
            # we? ~ C.

            if (lastLineSize > 0) { prompt.writeLine(b``) }
            return when (stdout<-(query)) ->
                prompt.readLine()

    return [makeRevokable(prompt, &enabled), cleanup]
