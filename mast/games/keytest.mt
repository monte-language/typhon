import "fun/mcurses" =~ [=> activateTerminal]
exports (main)

def blurb :Bytes := b`
Hi! This is a simple key-testing program. Tap any key on your input device,
and if this program senses anything, it'll print out what it sensed. To exit,
try to send SIGINT (^C).
`

def isQuit(event) :Bool as DeepFrozen:
    return event == ["DATA", b`$\x03`]

def main(_argv, => stdio) as DeepFrozen:
    return when (def term := activateTerminal(stdio)) ->
        def cursor := term<-outputCursor()
        cursor<-write(blurb)
        when (def source := term<-inputSource()) ->
            var more :Bool := true
            def testSink(event):
                if (isQuit(event)):
                    more := false
                cursor<-write(_makeBytes.fromStr(M.toString(event)) + b`$\n`)
            def go():
                return when (source<-(testSink)) ->
                    if (more) { go() } else { term<-quit() }
            when (go()) -> { 0 }
