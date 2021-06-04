exports (parseParens)

# We aim to transform a basic balanced-parens language from a flat Str to a
# nested tree of Lists.

def parseParens(s :Str) as DeepFrozen:
    def stack := [[].diverge()].diverge()
    var currentWord :Str := ""
    def endWord():
        if (!currentWord.isEmpty()):
            stack.last().push(currentWord)
            currentWord := ""

    for c in (s):
        switch (c):
            match =='(':
                endWord()
                stack.push([].diverge())
            match ==')':
                endWord()
                def l := stack.pop().snapshot()
                stack.last().push(l)
            match ==' ':
                endWord()
            match _:
                currentWord with= (c)

    return stack.last().last()
