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
    var lastLineWasEmpty :Bool := false
    var lineBuffer :Bytes := b``
    def whenDone

    def cleanup():
        if (!lastLineWasEmpty):
            stdout<-(b`$\n`)
        return when (stdout<-complete()) ->
            enabled := false
            bind whenDone := null

    object prompt:
        to whenDone():
            "A promise which resolves when the prompt is closed down."
            return whenDone

        to writeLine(bs :Bytes):
            "Write `bs` and start a new line."

            lastLineWasEmpty := bs.isEmpty()
            return stdout<-(bs + b`$\n`)

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

            if (!lastLineWasEmpty) { prompt.writeLine(b``) }
            return when (stdout<-(query)) ->
                prompt.readLine()

    return [makeRevokable(prompt, &enabled), cleanup]
