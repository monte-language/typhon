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

import "lib/tubes" =~ [
    => makeUTF8DecodePump :DeepFrozen,
    => makeUTF8EncodePump :DeepFrozen,
    => makeMapPump :DeepFrozen,
    => makeSplitPump :DeepFrozen,
    => makePumpTube :DeepFrozen,
    => chain :DeepFrozen]
import "lib/irc/user" =~ [=> sourceToUser :DeepFrozen]
import "lib/singleUse" =~ [=> makeSingleUse :DeepFrozen]
import "lib/tokenBucket" =~ [=> makeTokenBucket :DeepFrozen]
exports (makeIRCClient, connectIRCClient)



def makeLineTube() as DeepFrozen:
    return makePumpTube(makeSplitPump(b`$\r$\n`))


def makeIncoming() as DeepFrozen:
    return makePumpTube(makeUTF8DecodePump())


def makeOutgoing() as DeepFrozen:
    return makePumpTube(makeUTF8EncodePump())


def makeIRCClient(handler, Timer) as DeepFrozen:
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
        outgoing with= (l)
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

        to flowAborted(reason):
            traceln(`$IRCTube flow aborted: $reason`)
            drain := null

        to flowStopped(reason):
            traceln(`$IRCTube flow stopped: $reason`)
            drain := null

        # IRC wire stuff.

        to receive(item):
            switch (item):
                match `:@{via (sourceToUser) user} PRIVMSG @channel :@message`:
                    if (message[0] == '\x01'):
                        # CTCP.
                        handler.ctcp(IRCTube, user,
                                     message.slice(1, message.size() - 1))
                    else:
                        handler.privmsg(IRCTube, user, channel, message)

                match `:@{via (sourceToUser) user} JOIN @channel`:
                    def nick := user.getNick()
                    if (nickname == nick):
                        # This is pretty much the best way to find out what
                        # our reflected hostname is.
                        def host := user.getHost()
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

        to notice(channel, var message):
            def notice := `NOTICE $channel :`
            # nick!user@host
            def sourceLen := 4 + username.size() + nickname.size() + hostname.size()
            def paddingLen := 6 + 6 + 3 + 2 + 2
            # Not 512, because \r\n is 2 and will be added by line().
            def availableLen := 510 - sourceLen - paddingLen
            while (message.size() > availableLen):
                def slice := message.slice(0, availableLen)
                def i := slice.lastIndexOf(" ")
                def snippet := slice.slice(0, i)
                line(notice + snippet)
                message := message.slice(i + 1)
            line(notice + message)

        to ctcp(nick, message):
            # XXX CTCP quoting
            IRCTube.notice(nick, `$\x01$message$\x01`)

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


def connectIRCClient(client, endpoint) as DeepFrozen:
    def [fount, drain] := endpoint.connect()
    chain([
        fount,
        makeLineTube(),
        makeIncoming(),
        client,
        makeOutgoing(),
        drain,
    ])
