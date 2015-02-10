# Copyright (C) 2014 Google Inc. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may not
# use this file except in compliance with the License. You may obtain a copy
# of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations
# under the License.

def [=> simple__quasiParser] := import("lib/simple")
def [=> Bytes, => b__quasiParser] | _ := import("lib/bytes")
def [=> UTF8Decode, => UTF8Encode] | _ := import("lib/utf8")
def [=> nullPump] := import("lib/tubes/nullPump")
def [=> makeMapPump] := import("lib/tubes/mapPump")
def [=> makePumpTube] := import("lib/tubes/pumpTube")
def [=> makeUnpauser] := import("lib/tubes/unpauser")


def splitAt(needle, var haystack):
    def pieces := [].diverge()
    escape ej:
        while (true):
            def b`@head$needle@tail` exit ej := haystack
            pieces.push(head)
            haystack := tail
    return [pieces.snapshot(), haystack]


def testSplitAtColons(assert):
    def specimen := b`colon:splitting:things`
    def [pieces, leftovers] := splitAt(b`:`, specimen)
    assert.equal(pieces, [b`colon`, b`splitting`])
    assert.equal(leftovers, b`things`)


def testSplitAtWide(assert):
    def specimen := b`it's##an##octagon#not##an#octothorpe`
    def [pieces, leftovers] := splitAt(b`##`, specimen)
    assert.equal(pieces, [b`it's`, b`an`, b`octagon#not`])
    assert.equal(leftovers, b`an#octothorpe`)


unittest([
    testSplitAtColons,
    testSplitAtWide,
])


def makeSplittingPump():
    var buf := []

    return object splitPump extends nullPump:
        to received(item):
            buf += item
            def [pieces, leftovers] := splitAt(b`$\r$\n`, buf)
            buf := leftovers
            return pieces


def makeLineTube():
    return makePumpTube(makeSplittingPump())


def makeIncoming():
    return makePumpTube(makeMapPump(UTF8Decode))


def makeOutgoing():
    return makePumpTube(makeMapPump(UTF8Encode))


def makeIRCClient(handler):
    var drain := null
    var pauses :Int := 0
    var nick :Str := handler.getNick()
    var channels := [].asMap()
    var outgoing := []

    def line(l :Str):
        outgoing := outgoing.with(l)
        if (drain != null && pauses == 0):
            for line in outgoing:
                traceln("Sending line: " + line)
                drain.receive(line + "\r\n")
            outgoing := []

    return object IRCTube:
        # Tube methods.

        to flowTo(newDrain):
            drain := newDrain
            def rv := drain.flowingFrom(IRCTube)
            IRCTube.login()
            return rv

        to flowingFrom(fount):
            traceln("Flowing from:", fount)
            return IRCTube

        to pauseFlow():
            pauses += 1
            return makeUnpauser(IRCTube.unpause)

        to unpause():
            pauses -= 1
            if (drain != null && pauses == 0):
                for line in outgoing:
                    traceln("Sending line: " + line)
                    drain.receive(line + "\r\n")
                outgoing := []

        # IRC wire stuff.

        to receive(item):
            switch (item):
                match `:@source PRIVMSG @channel :@message`:
                    handler.privmsg(IRCTube, source, channel, message)

                match `:@nick!@{_} JOIN @channel`:
                    channels[channel][nick] := []
                    traceln(`$nick joined $channel`)

                match `:@nick!@{_} QUIT @{_}`:
                    for channel in channels:
                        if (channel.contains(nick)):
                            channel.removeKey(nick)
                    traceln(`$nick has quit`)

                match `:@nick!@{_} PART @channel @{_}`:
                    if (channels[channel].contains(nick)):
                        channels[channel].removeKey(nick)
                    traceln(`$nick has parted $channel`)

                match `:@oldNick!@{_} NICK :@newNick`:
                    for channel in channels:
                        escape ej:
                            def mode := channel.fetch(oldNick, ej)
                            channel.removeKey(oldNick)
                            channel[newNick] := mode
                    traceln(`$oldNick is now known as $newNick`)

                match `PING @ping`:
                    traceln(`Server ping/pong: $ping`)
                    IRCTube.pong(ping)

                # XXX @_
                match `:@{_} 004 $nick @hostname @version @userModes @channelModes`:
                    traceln(`Logged in as $nick!`)
                    traceln(`Server $hostname ($version)`)
                    traceln(`User modes: $userModes`)
                    traceln(`Channel modes: $channelModes`)
                    handler.loggedIn(IRCTube)

                match `@{_} 353 $nick @{_} @channel :@nicks`:
                    def channelNicks := channels[channel]
                    def nickList := nicks.split(" ")
                    for nick in nickList:
                        channelNicks[nick] := null
                    traceln(`Current nicks on $channel: $channelNicks`)

                match _:
                    traceln(item)

        # Call these to make stuff happen.

        to pong(ping):
            line(`PONG $ping`)

        to part(channel :Str, message :Str):
            line(`PART $channel :$message`)

        to quit(message :Str):
            for channel => _ in channels:
                IRCTube.part(channel, message)
            line(`QUIT :$message`)

        to login():
            line(`NICK $nick`)
            line("USER monte localhost irc.freenode.net :Monte")
            line("PING :suchPing") 

        to join(var channel :Str):
            if (channel[0] != '#'):
                channel := "#" + channel
            line(`JOIN $channel`)
            channels := channels.with(channel, [].asMap().diverge())

        to say(channel, message):
            line(`PRIVMSG $channel :$message`)

        # Data accessors.

        to getUsers(channel, ej):
            return channels.fetch(channel, ej)


def chain([var fount] + drains):
    for drain in drains:
        fount := fount<-flowTo(drain)
    return fount

def connectIRCClient(client, endpoint):
    endpoint.connect()
    def [fount, drain] := endpoint.connect()
    chain([
        fount,
        makeLineTube(),
        makeIncoming(),
        client,
        makeOutgoing(),
        drain,
    ])

[=> makeIRCClient, => connectIRCClient]
