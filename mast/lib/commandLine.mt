import "lib/wrappers" =~ [=> makeRevokable]
exports (makePrompt)

# This magic sequence clears the current line of stdout and moves the cursor
# to the beginning of the line. ~ C.
def clearLine :Bytes := b`$\x1b[2K` + b`$\r`

def makePrompt(stdio) as DeepFrozen:
    "
    A basic CLI toolkit on `stdio`.

    Makes a pair of a prompt and a cleanup runnable.
    "

    def stdin := stdio.stdin()
    def stdout := stdio.stdout()
    var enabled :Bool := true
    var lineBuffer :Bytes := b``
    def whenDone

    def cleanup():
        return when (stdout<-complete()) ->
            enabled := false
            bind whenDone := null

    object prompt:
        to whenDone():
            "A promise which resolves when the prompt is closed down."

            return whenDone

        to writeLine(bs :Bytes):
            "Write `bs` and start a new line."

            return stdout<-(clearLine + bs + b`$\n`)

        to setLine(bs :Bytes):
            "
            Change the current line to `bs`.

            It is implied that this change is temporary and that a
            `.writeLine` will come later to set the current line permanently.
            "

            return stdout<-(clearLine + bs)

        to readLine() :Vow[Bytes]:
            "Read a line of `Bytes`."

            # Maybe we've already read a line?
            if (lineBuffer =~ b`@line$\n@rest`):
                lineBuffer := rest
                return line

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

            return when (stdout<-(clearLine + query)) ->
                prompt.readLine()

    return [makeRevokable(prompt, &enabled), cleanup]
