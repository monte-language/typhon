import "lib/codec/utf8" =~ [=> UTF8 :DeepFrozen]
import "lib/streams" =~ [=> Sink :DeepFrozen]

exports (activateTerminal)

def CSI :Bytes := b`$\x1b[`
def KEY_NAMES :List[Str] := [
    "UP_ARROW", "DOWN_ARROW", "RIGHT_ARROW", "LEFT_ARROW",
    "HOME", "INSERT", "DELETE", "END", "PGUP", "PGDN", "NUMPAD_MIDDLE",
    "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9",
    "F10", "F11", "F12"]

def dec(x :Int) :Bytes as DeepFrozen:
    def s := M.toString(x)
    return UTF8.encode(s, null)

def undec(bs :Bytes, ej) :Int as DeepFrozen:
    return _makeInt(UTF8.decode(bs, ej), ej)

def makeTerminalPair(stdin, stdout) as DeepFrozen:

    var cursorReports := [].diverge()
    object termout:
        to write(bytes):
            stdout(bytes)

        to clear():
            stdout(b`${CSI}2J`)

        to enterAltScreen():
            stdout(b`${CSI}?1049h`)

        to leaveAltScreen():
            stdout(b`${CSI}?1049l`)

        to move(y :Int, x :Int):
            stdout(b`${CSI}${dec(y)};${dec(x)}H`)

        to moveLeft(n):
            stdout(b`${CSI}${dec(n)}D`)

        to eraseLeft():
            stdout(b`${CSI}1K`)

        to eraseRight():
            stdout(b`${CSI}0K`)

        to setMargins(top :Int, bottom :Int):
            stdout(b`${CSI}${dec(top)};${dec(bottom)}r`)

        to insertLines(n :Int):
            stdout(b`${CSI}${dec(n)}L`)

        to deleteLines(n :Int):
            stdout(b`${CSI}${dec(n)}M`)

        to eraseLine():
            stdout(b`${CSI}K`)

        to getCursorReport():
            def [response, r] := Ref.promise()
            cursorReports.insert(0, r)
            stdout(b`${CSI}6n`)
            return response

        to hideCursor():
            stdout(b`${CSI}?25l`)

        to showCursor():
            stdout(b`${CSI}?25h`)

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

    object controlSequenceParser:
        to "~"(seq, fail):
            return tildeSeqs.fetch(
                try {
                    _makeInt(UTF8.decode(seq, fail))
                } catch _ {
                    throw.eject(fail, `Not an integer: $seq`)
                }, fail)

        to R(seq, fail):
            if (cursorReports.size() == 0):
                throw.eject(fail, `Unsolicited cursor report`)
            def [via (undec) row,
                 via (undec) col] exit fail := seq.split(b`;`)
            cursorReports.pop().resolve([row, col])

        match [verb, [_, fail], _]:
            simpleControlSeqs.fetch(verb, fail)


    object termin:
        to flowTo(sink):
            def [terminVow, terminR] := Ref.promise()
            var state := "data"
            var escBuffer := []
            var writeStart := 0
            var writeEnd := null
            object terminalSink as Sink:
                to complete():
                    terminR.resolve(null)
                    return sink.complete()
                to abort(p):
                    terminR.smash(p)
                    return sink.abort(p)

                to run(packet):
                    if (Ref.isResolved(terminVow)):
                        return
                    def deliver(msg):
                        if (msg[1] == null):
                            # Oh well, try again
                            stdin <- (terminalSink)
                            return
                        return when (sink <- (msg)) ->
                            def p0 := stdin <- (terminalSink)
                            null
                        catch p:
                            traceln.exception(p)
                            terminR.smash(p)
                            sink.abort(p)
                            Ref.broken(p)
                    def handleControlSequence(content, terminator):
                        escape e:
                            def keyname := M.call(controlSequenceParser,
                                                  terminator,
                                                  [content, throw],
                                                  [].asMap())
                            return deliver(["KEY", keyname])
                        catch p:
                            traceln(p)
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

            return when (stdin <- (terminalSink)) ->
                terminVow
            catch problem:
                traceln.exception(problem)
                terminR.smash(problem)
                Ref.broken(problem)
    return [termin, termout]


def activateTerminal(stdio) as DeepFrozen:
    def stdin := stdio.stdin()
    def stdout := stdio.stdout()
    # if (!(stdin.isATTY() && stdout.isATTY())):
    #     stdout(b`A terminal is required$\n`)
    #     return 1
    def [width, height] := stdout.getWindowSize()
    if (!(width >= 80 && height >= 24)):
        throw("Terminal must be at least 80x24.")
    stdin.setRawMode(true)
    return [[width, height], makeTerminalPair(stdin, stdout)]
