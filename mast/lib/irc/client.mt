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

def [=> Bytes, => b__quasiParser] | _ := import("lib/bytes")
def [=> UTF8] | _ := import("lib/codec/utf8")
def [
    => makeUTF8DecodePump,
    => makeUTF8EncodePump
] | _ := import("lib/tubes/utf8")
def [=> nullPump] := import("lib/tubes/nullPump")
def [=> makeMapPump] := import("lib/tubes/mapPump")
def [=> makePumpTube] := import("lib/tubes/pumpTube")
def [=> makeSingleUse] := import("lib/singleUse")
def [=> makeTokenBucket] := import("lib/tokenBucket")


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
    return makePumpTube(makeUTF8DecodePump())


def makeOutgoing():
    return makePumpTube(makeUTF8EncodePump())


def makeIRCClient(handler):
    var drain := null
    var pauses :Int := 0

    var nickname :Str := handler.getNick()
    # This hostname will be refined later as the IRC server gives us more
    # feedback on what our reverse hostname looks like.
    var hostname :Str := "localhost"
    def username :Str := "monte"
    var channels := [].asMap()
    var outgoing := []

    # Pending events.
    def pendingChannels := [].asMap().diverge()

    # Five lines of burst and a new line every two seconds.
    def tokenBucket := makeTokenBucket(5, 2.0)
    tokenBucket.start(Timer)

    def flush() :Void:
        if (drain != null && pauses == 0):
            for i => line in outgoing:
                traceln("Sending line: " + line)
                if (tokenBucket.deduct(1)):
                    drain.receive(line + "\r\n")
                else:
                    traceln("Rate-limited")
                    outgoing := outgoing.slice(i)
                    when (tokenBucket.ready()) ->
                        flush()
                    return
            outgoing := []

    def line(l :Str) :Void:
        outgoing := outgoing.with(l)
        flush()

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
            def singleUse := makeSingleUse(IRCTube.unpause)
            return object unpauser:
                to unpause():
                    singleUse()

        to unpause():
            pauses -= 1
            if (drain != null && pauses == 0):
                for line in outgoing:
                    traceln("Sending line: " + line)
                    drain.receive(line + "\r\n")
                outgoing := []

        to flowStopped(reason):
            traceln(`$IRCTube flow stopped: $reason`)
            drain := null

        # IRC wire stuff.

        to receive(item):
            switch (item):
                match `:@source PRIVMSG @channel :@message`:
                    handler.privmsg(IRCTube, source, channel, message)

                match `:@nick!@{_}@@@host JOIN @channel`:
                    if (nickname == nick):
                        # This is pretty much the best way to find out what
                        # our reflected hostname is.
                        traceln(`Refined hostname from $hostname to $host`)
                        hostname := host

                        IRCTube.joined(channel)
                    # We have to call joined() prior to accessing this map.
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

                match `:@nick!@{_} PART @channel`:
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
                match `:@{_} 004 $nickname @hostname @version @userModes @channelModes`:
                    traceln(`Logged in as $nickname!`)
                    traceln(`Server $hostname ($version)`)
                    traceln(`User modes: $userModes`)
                    traceln(`Channel modes: $channelModes`)
                    handler.loggedIn(IRCTube)

                match `@{_} 353 $nickname @{_} @channel :@nicks`:
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
            tokenBucket.stop()

        to login():
            line(`NICK $nickname`)
            line(`USER $username $hostname irc.freenode.net :Monte`)
            line("PING :suchPing") 

        to join(var channel :Str):
            if (channel[0] != '#'):
                channel := "#" + channel
            line(`JOIN $channel`)

        to say(channel, var message):
            def privmsg := `PRIVMSG $channel :`
            # nick!user@host
            def sourceLen := 4 + username.size() + nickname.size() + hostname.size()
            def paddingLen := 6 + 6 + 3 + 2 + 2
            # Not 512, because \r\n is 2 and will be added by line().
            def availableLen := 510 - sourceLen - paddingLen
            while (message.size() > availableLen):
                def slice := message.slice(0, availableLen)
                def i := slice.lastIndexOf(" ")
                def snippet := slice.slice(0, i)
                line(privmsg + snippet)
                message := message.slice(i + 1)
            line(privmsg + message)

        # Data accessors.

        to getUsers(channel, ej):
            return channels.fetch(channel, ej)

        # Low-level events.

        to joined(channel :Str):
            traceln(`I joined $channel`)
            channels := channels.with(channel, [].asMap().diverge())

            if (pendingChannels.contains(channel)):
                pendingChannels[channel].resolve(null)
                pendingChannels.removeKey(channel)

        # High-level events.

        to hasJoined(channel :Str):
            if (channels.contains(channel)):
                return null
            else:
                IRCTube.join(channel)
                def [p, r] := Ref.promise()
                pendingChannels[channel] := r
                return p


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
