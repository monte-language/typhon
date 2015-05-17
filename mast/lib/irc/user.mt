def makeUser(nick :Str, user :Str, host :Str):
    return object completeUser:
        to _printOn(out):
            out.print(`$nick!$user@@$host`)

        to _uncall():
            return [makeUser, [nick, user, host]]

        to getNick() :Str:
            return nick

        to getUser() :Str:
            return user

        to getHost() :Str:
            return host

def testUserEquality(assert):
    def first := makeUser("first", "second", "example.com")
    def second := makeUser("first", "second", "example.com")
    assert.equal(first, second)

unittest([testUserEquality])


def sourceToUser(specimen, ej):
    switch (specimen):
        match `@nick!@user@@@host`:
            return makeUser(nick, user, host)
        match _:
            throw.eject(ej, "Could not parse source into user")

def testSourceToUser(assert):
    assert.ejects(fn ej {def via (sourceToUser) x exit ej := "asdf"})
    assert.doesNotEject(fn ej {def via (sourceToUser) x exit ej := "nick!user@host"})

unittest([testSourceToUser])


[=> makeUser, => sourceToUser]
