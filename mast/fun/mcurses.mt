import "lib/codec/utf8" =~ [=> UTF8]
import "lib/streams" =~ [=> Sink, => Source]
exports (activateTerminal)

def CSI :Bytes := b`$\x1b[`

def dec(x :Int) :Bytes as DeepFrozen:
    def s := M.toString(x)
    return UTF8.encode(s, null)

def undec(bs :Bytes, ej) :Int as DeepFrozen:
    return _makeInt(UTF8.decode(bs, ej), ej)

def lowFKeys :Map[Int, Str] := [
    80 => "F1", 81 => "F2",
    82 => "F3", 83 => "F4"]

def tildeSeqs :Map[Int, Str] := [
    1 => "HOME", 2 => "INSERT", 3 => "DELETE", 4 => "END",
                  5 => "PGUP", 6 => "PGDN",
                  11 => "F1", 12 => "F2", 13 => "F3", 14 => "F4",
                  15 => "F5", 17 => "F6", 18 => "F7", 19 => "F8",
                  20 => "F9", 21 => "F10", 23 => "F11", 24 => "F12"]

def simpleControlSeqs :Map[Str, Str] := [
    "A" => "UP_ARROW", "B" => "DOWN_ARROW",
    "C" => "RIGHT_ARROW", "D" => "LEFT_ARROW",
    "E" => "NUMPAD_MIDDLE", "F" => "END",
    "H" => "HOME"]

def makeInputSource(stdin, cursorReports) as DeepFrozen:
    object controlSequenceParser:
        to "~"(seq, fail):
            return tildeSeqs.fetch(
                try {
                    _makeInt(UTF8.decode(seq, fail))
                } catch _ {
                    throw.eject(fail, `Not an integer: $seq`)
                }, fail)

        to R(seq, fail):
            if (cursorReports.isEmpty()):
                throw.eject(fail, `Unsolicited cursor report`)
            def [via (undec) row,
                 via (undec) col] exit fail := seq.split(b`;`)
            cursorReports.pop().resolve([row, col])

        match [verb, [_, fail], _]:
            simpleControlSeqs.fetch(verb, fail)

    def bufferedEvents := [].diverge()
    var state := "data"
    var escBuffer :List[Int] := []
    var writeStart :NullOk[Int] := 0
    var writeEnd :NullOk[Int] := null
    def pump():
        object bufferingSink as Sink:
            to complete():
                return stdin.complete()

            to abort(problem):
                return stdin.abort(problem)

            to run(packet):
                def deliver(message) { bufferedEvents.insert(0, message) }
                def handleControlSequence(content, terminator):
                    def keyname := M.call(controlSequenceParser,
                                          terminator,
                                          [content, throw],
                                          [].asMap())
                    deliver(["KEY", keyname])
                def handleLowFunction(ch):
                    if (!lowFKeys.contains(ch)):
                        traceln(`Unrecognized ^[O sequence`)
                        return
                    def k := lowFKeys[ch]
                    return deliver(["KEY", k])
                def handleText(data):
                    return deliver(["DATA", data])

                for i => byte in (packet):
                    switch (state):
                        match =="data":
                            if (byte == 0x1b):
                                state := "escaped"
                                if (writeEnd != null):
                                     handleText(packet.slice(writeStart,
                                                             writeEnd))
                                     writeStart := null
                                     writeEnd := null
                            else:
                                writeEnd := i
                        match =="escaped":
                            if (byte == '['.asInteger()):
                                state := "bracket-escaped"
                            else if (byte == 'O'.asInteger()):
                                state := "low-function-escaped"
                            else:
                                state := "data"
                                writeStart := i + 1
                                writeEnd := null
                                deliver(["DATA", b`$\x1b`])
                        match =="bracket-escaped":
                            if (byte == 'O'.asInteger()):
                                state := "low-function-escaped"
                            else if (('A'.asInteger()..'Z'.asInteger()
                                     ).contains(byte) ||
                                     byte == '~'.asInteger()):
                                handleControlSequence(
                                    _makeBytes.fromInts(escBuffer),
                                    _makeStr.fromChars(['\x00' + byte]))
                                escBuffer := []
                                writeStart := i + 1
                                state := "data"
                            else:
                                escBuffer with= (byte)

                        match =="low-function-escaped":
                            handleLowFunction(byte)
                            writeStart := i + 1
                            state := "data"
                        match s:
                            throw(`Illegal state $s`)
                if (state == "data"):
                    if (writeStart != packet.size()):
                        handleText(packet.slice(writeStart))
                    writeStart := 0
                    writeEnd := null

        return when (stdin<-(bufferingSink)) ->
            if (bufferedEvents.isEmpty()) { pump<-() } else {
                bufferedEvents.pop()
            }

    return def inputSource(sink) as Source:
        return when (def next := pump<-()) -> { sink(next) }

def makeOutputCursor(stdout, cursorReports) as DeepFrozen:
    return object outputCursor:
        to write(bytes :Bytes):
            return stdout<-(bytes)

        to clear():
            return stdout<-(b`${CSI}2J`)

        to enterAltScreen():
            return stdout<-(b`${CSI}?1049h`)

        to leaveAltScreen():
            return stdout<-(b`${CSI}?1049l`)

        to move(y :Int, x :Int):
            return stdout<-(b`${CSI}${dec(y)};${dec(x)}H`)

        to moveLeft(n :Int):
            return stdout<-(b`${CSI}${dec(n)}D`)

        to eraseLeft():
            return stdout<-(b`${CSI}1K`)

        to eraseRight():
            return stdout<-(b`${CSI}0K`)

        to setMargins(top :Int, bottom :Int):
            return stdout<-(b`${CSI}${dec(top)};${dec(bottom)}r`)

        to insertLines(n :Int):
            return stdout<-(b`${CSI}${dec(n)}L`)

        to deleteLines(n :Int):
            return stdout<-(b`${CSI}${dec(n)}M`)

        to eraseLine():
            return stdout<-(b`${CSI}K`)

        to getCursorReport():
            cursorReports.insert(0, def response)
            stdout(b`${CSI}6n`)
            return response

        to hideCursor():
            return stdout<-(b`${CSI}?25l`)

        to showCursor():
            return stdout<-(b`${CSI}?25h`)

def activateTerminal(stdio) as DeepFrozen:
    def stdin := stdio.stdin()
    def stdout := stdio.stdout()
    # XXX Typhon bug; always returns false for some reason
    # if (!stdin.isATTY() || !stdout.isATTY()):
    #     throw(`Cannot activate terminal on non-TTY`)

    def [var width :Int, var height :Int] := stdout.getWindowSize()
    def sigwinch := stdout.whenWindowSizeChanges(fn _ {
        def [w, h] := stdout.getWindowSize()
        width := w
        height := h
    })
    return when (stdin<-setRawMode(true)) ->
        def cursorReports := [].diverge()
        def inputSource := makeInputSource(stdin, cursorReports)
        def outputCursor := makeOutputCursor(stdout, cursorReports)
        object term:
            to quit():
                sigwinch.disarm()
                stdin<-setRawMode(false)

            to height() :Int:
                return height

            to width() :Int:
                return width

            to inputSource():
                return inputSource

            to outputCursor():
                return outputCursor
