import "fun/mcurses" =~ [=> activateTerminal]
import "games/wid" =~ ["ASTBuilder" => wid]
import "lib/codec/utf8" =~ [=> UTF8]
import "lib/welford" =~ [=> makeWelford]
exports (main)

def flowText(s :Str, width :Int) :List[Str] as DeepFrozen:
    def lines := [].diverge()
    var currentLine := [].diverge()
    var currentLength := 0
    for word in (s.replace("\r", " ").split(" ")):
        if (word.size() + 1 + currentLength > width):
            lines.push(" ".join(currentLine))
            currentLine := [].diverge()
            currentLength := 0
        currentLine.push(word)
        currentLength += word.size() + 1
    lines.push(" ".join(currentLine))
    return lines.snapshot()

def sizeOf(width :Int, height :Int) as DeepFrozen:
    "
    Given a `width` by `height` canvas, determine how much space will actually
    be used during a draw, and additionally which sizing mode will be used for
    layout.
    "

    return object sizing as DeepFrozen:
        to Text(s :Str):
            def lines := flowText(s, width)
            var maxWidth := 0
            for line in (lines):
                maxWidth max= (line.size())
            return [maxWidth, lines.size()]

        to Columns(widgets :List):
            def columnWidth := width // widgets.size()
            var maxHeight := 0
            for widget in (widgets):
                def [_, h] := widget.walk(sizeOf(columnWidth, height))
                maxHeight max= (h)
            return [columnWidth, maxHeight]

        to Pile(widgets :List):
            var maxWidth := 0
            var totalHeight := 0
            for widget in (widgets):
                def [w, h] := widget.walk(sizeOf(width, height))
                def newHeight := totalHeight + h
                if (newHeight > height) { break }
                maxWidth max= (w)
                totalHeight := newHeight
            return [maxWidth, totalHeight]

        to Frame(_header, _body, _footer):
            return [width, height]

        to LineBox(widget):
            def [w, h] := widget.walk(sizeOf(width - 2, height - 2))
            return [w + 2, h + 2]

# XXX common code with games/animate
def startCanvasMode(cursor) as DeepFrozen:
    traceln("starting canvas mode")
    return when (cursor<-enterAltScreen(), cursor<-hideCursor()) -> { null }

def stopCanvasMode(cursor) as DeepFrozen:
    return when (cursor<-showCursor(), cursor<-leaveAltScreen()) ->
        traceln("stopping canvas mode")

def renderOnto(canvas) as DeepFrozen:
    return object renderer:
        to Text(text :Str):
            def lines := flowText(text, canvas.width())
            return promiseAllFulfilled([for i => line in (lines) {
                def bs := UTF8.encode(line, null)
                canvas(i, bs + b` ` * (canvas.width() - line.size()))
            }])

        to Columns(widgets :List):
            def width := canvas.width() // widgets.size()
            def height := canvas.height()
            for i => widget in (widgets):
                widget.walk(renderOnto(canvas.sub(width * i, 0, width,
                                                  height)))

        to Pile(widgets :List):
            # XXX algorithm overlaps with sizeof()
            def width := canvas.width()
            def height := canvas.height()
            var offset := 0
            for widget in (widgets):
                def [_, h] := widget.walk(sizeOf(width, height - offset))
                offset += h
                if (offset > height) { break }
                widget.walk(renderOnto(canvas.sub(0, offset, width, h)))

        to Frame(header, body, footer):
            def width := canvas.width()
            def height := canvas.height()
            def headerHeight := if (header != null) {
                header.walk(sizeOf(width, height))[1]
            } else { 0 }
            def footerHeight := if (footer != null) {
                footer.walk(sizeOf(width, height))[1]
            } else { 0 }
            def frameHeight := height - headerHeight - footerHeight
            if (headerHeight.aboveZero()):
                header.walk(renderOnto(canvas.sub(0, 0, width, headerHeight)))
            if (frameHeight.aboveZero()):
                body.walk(renderOnto(canvas.sub(0, headerHeight, width,
                                                frameHeight)))
            if (footerHeight.aboveZero()):
                footer.walk(renderOnto(canvas.sub(0, height - footerHeight,
                                                  width, footerHeight)))

        to LineBox(w):
            def width := canvas.width()
            def height := canvas.height()
            def headerRow := b`+` + b`-` * (width - 2) + b`+`
            def plainRow := b`|` + b` ` * (width - 2) + b`|`
            def rv := [
                canvas(0, headerRow),
                canvas(height - 1, headerRow),
            ] + [for row in (1..!(height - 1)) canvas(row, plainRow)]
            def sub := w.walk(renderOnto(canvas.sub(1, 1, width - 2, height - 2)))
            return promiseAllFulfilled(rv.with(sub))

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

            to sub(x :Pos, y :Pos, w :Pos, h :Pos):
                return makeCanvas.atOffset(cursor, x0 + x, y0 + y, w, h)

def makeREPL(Timer, unsealException) as DeepFrozen:
    def rt := makeWelford()
    def et := makeWelford()
    var command :Str := ""
    var done :Bool := false
    var result := null

    return object repl:
        to done() :Bool:
            return done

        to asWidget():
            def now := Timer.unsafeNow()
            return wid.LineBox(wid.Frame(
                wid.LineBox(wid.Text("Experimental REPL")),
                wid.LineBox(wid.Pile([
                    wid.Text(`⛰  $command`),
                    wid.Text(`Result: $result`),
                ])),
                wid.LineBox(wid.Columns([
                    wid.Text(`Render time: ${(rt.mean() * 1000).floor()}ms`),
                    wid.Text(`Eval time: ${(et.mean() * 1000).floor()}ms`),
                    wid.Text(`System clock: $now`),
                ])),
            ))

        to timeTaken(t :Double):
            rt(t)

        to run(event):
            if (event =~ [=="DATA", c]):
                switch (c):
                    match b`$\x03`:
                        # ^C
                        done := true
                    match b`$\r`:
                        # Enter
                        def expr := command
                        def t := Timer.measureTimeTaken(fn {
                            result := eval(expr, safeScope)
                        })
                        when (t) -> { et(t) } catch problem {
                            result := `Error in eval(): ${unsealException(problem)}`
                        }
                        command := ""
                    match b`$\x7f`:
                        # Backspace
                        command slice= (0, command.size() - 1)
                    match _ :(b` `..b`~`):
                        # Printable characters.
                        command with= ('\x00' + c[0])

        to complete():
            done := true

        to abort(problem):
            result := `Error with event: ${unsealException(problem)}`

def main(_argv, => Timer, => stdio, => unsealException) as DeepFrozen:
    def term := activateTerminal(stdio)
    def cursor := term<-outputCursor()
    return when (term) ->
        def source := term<-inputSource()
        when (source, startCanvasMode(cursor)) ->
            def repl := makeREPL(Timer, unsealException)
            def draw():
                # XXX width/height info should be passed to REPL?
                def widget := repl.asWidget()
                def canvas := makeCanvas(cursor, term.width(), term.height())
                def startTime := Timer.unsafeNow()
                return when (widget.walk(renderOnto(canvas))) ->
                    def stopTime := Timer.unsafeNow()
                    repl.timeTaken(stopTime - startTime)
            def redrawRegularly():
                return when (Timer.fromNow(1.0)) ->
                    if (!repl.done()):
                        when (draw()) -> { redrawRegularly() }
            def go():
                return when (draw(), source<-(repl)) ->
                    if (!repl.done()) { go() } else {
                        when (stopCanvasMode(cursor)) -> { term<-quit() }
                    }
            when (go(), redrawRegularly()) ->
                0
            catch problem:
                when (stopCanvasMode(cursor), term<-quit()) ->
                    traceln.exception(problem)
                    1
