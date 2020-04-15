import "fun/mcurses" =~ [=> activateTerminal]
import "games/wid" =~ ["ASTBuilder" => wid]
import "lib/codec/utf8" =~ [=> UTF8]
exports (main)

def blurb :Str := `
Hi! This is a simple key-testing program. Tap any key on your input device,
and if this program senses anything, it'll print out what it sensed. To exit,
try to send SIGINT (^C).
`

object sizing as DeepFrozen:
    to Text(_):
        return wid.Flow()

    to Frame(_, _, _):
        return wid.Box()

def isQuit(event) :Bool as DeepFrozen:
    return event == ["DATA", b`$\x03`]

# XXX common code with games/animate
def startCanvasMode(cursor) as DeepFrozen:
    return when (cursor<-enterAltScreen(), cursor<-hideCursor()) -> { null }

def stopCanvasMode(cursor) as DeepFrozen:
    return when (cursor<-showCursor(), cursor<-leaveAltScreen()) -> { null }

def renderOnto(canvas) as DeepFrozen:
    return object renderer:
        to Text(text :Str):
            return promiseAllFulfilled([for i => line in (text.split("\n")) {
                def bs := UTF8.encode(line, null)
                canvas(i, bs + b` ` * (canvas.width() - bs.size()))
            }])

        to Frame(_, _, _):
            null

def Pos :DeepFrozen := (Int >= 0)

object makeCanvas as DeepFrozen:
    to run(cursor, width :Pos, height :Pos):
        return makeCanvas.atOffset(cursor, 0, 0, width, height)

    to atOffset(cursor, x0 :Pos, y0 :Pos, width :Pos, height :Pos):
        def rows := ([b` ` * width] * height).diverge()
        return object canvas:
            to run(row :Pos, line :Bytes):
                return promiseAllFulfilled([
                    # NB: canvas is zero-indexed, for sanity, but ANSI escape
                    # codes are one-indexed. This justifies the fencepost.
                    cursor<-move(y0 + row + 1, x0 + 1),
                    cursor<-write(line),
                ])

            to width() :Int:
                return width

            to height() :Int:
                return height

def main(_argv, => stdio) as DeepFrozen:
    def term := activateTerminal(stdio)
    def cursor := term<-outputCursor()
    return when (term) ->
        def source := term<-inputSource()
        when (source, startCanvasMode(cursor)) ->
            var widget := wid.Text(blurb)
            def draw():
                def canvas := makeCanvas(cursor, term.width(), term.height())
                return widget(renderOnto(canvas))
            var more :Bool := true
            def testSink(event):
                if (isQuit(event)):
                    more := false
                widget := wid.Text(`Got event: $event`)
                return draw()
            def go():
                return when (draw(), source<-(testSink)) ->
                    if (more) { go() } else {
                        when (stopCanvasMode(cursor)) -> { term<-quit() }
                    }
            when (go()) -> { 0 }
    catch problem:
        when (stopCanvasMode(cursor), term<-quit()) ->
            traceln.exception(problem)
            1
