# Copyright (C) 2015 Google Inc. All rights reserved.
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

# This benchmark is adapted from the Python version. It deliberately chooses
# some Monte idioms instead of slavishly translating Python, but doesn't make
# any choices that would speed things up by cheating.

def [=> makeEnum] := import.script("lib/enum")

# Task states.
def [TaskType, BLANK, IDLE, WORK, HANDLERA, HANDLERB, DEVA, DEVB] := makeEnum(
    ["Blank", "Idle", "Work", "Handler A", "Handler B", "Device A", "Device B"])

# Types of packet.
def [PacketType, KDEV, KWORK] := makeEnum(["Device Packet", "Work Packet"])

def BUFSIZE :Int := 4

# Work tracing.
var traces := ""
def trace(c :Char):
    traces += c
    if (traces.size() >= 50):
        # traceln(traces)
        traces := ""


def makePacket(var link, var ident :TaskType, kind :PacketType):
    var datum :Int := 0
    var data :List[Int] := [0] * BUFSIZE

    return object packet:
        to getLink():
            return link

        to setLink(p):
            link := p

        to getIdent() :TaskType:
            return ident

        to setIdent(i :TaskType):
            ident := i

        to getDatum() :Int:
            return datum

        to setDatum(d :Int):
            datum := d

        to getData(index :Int) :Int:
            return data[index]

        to setData(index :Int, d :Int):
            data := data.with(index, d)

        to getKind() :PacketType:
            return kind

        to appendTo(last):
            link := null
            if (last == null):
                return packet
            else:
                var p := last
                var next := p.getLink()

                while (next != null):
                    p := next
                    next := p.getLink()

                p.setLink(packet)
                return last


# Task records.

def makeDeviceTaskRecord():
    return ["pending" => null].diverge()

def makeIdleTaskRecord():
    return ["control" => 1, "count" => 10000].diverge()

def makeHandlerTaskRecord():
    return ["workIn" => null, "deviceIn" => null].diverge()

def makeWorkerTaskRecord():
    return ["destination" => HANDLERA, "count" => 0].diverge()


def makeTaskState():
    var packetPending :Bool := true
    var taskWaiting :Bool := false
    var taskHolding :Bool := false

    return object taskState:
        to _printOn(out):
            out.print(
                `<Task state ($packetPending, $taskWaiting, $taskHolding)`)

        to setPacketPending():
            packetPending := true

        to setTaskWaiting():
            taskWaiting := true

        to setTaskHolding():
            taskHolding := true

        to clearTaskHolding():
            taskHolding := false

        to packetPending():
            packetPending := true
            taskWaiting := false
            taskHolding := false
            return taskState

        to waiting():
            packetPending := false
            taskWaiting := true
            taskHolding := false
            return taskState

        to running():
            packetPending := false
            taskWaiting := false
            taskHolding := false
            return taskState

        to waitingWithPacket():
            packetPending := true
            taskWaiting := true
            taskHolding := false
            return taskState

        # XXX incorrect operators
        to isTaskHoldingOrWaiting() :Bool:
            return taskHolding | (!packetPending & taskWaiting)

        # XXX incorrect operators
        to isWaitingWithPacket() :Bool:
            return packetPending & taskWaiting & !taskHolding


var taskTab :Map[TaskType, Any] := [].asMap()
var taskList := null
var holdCount :Int := 0
var qpktCount :Int := 0


def findtcb(id :TaskType):
    return taskTab.fetch(id, null)


# Tasks.
def makeTaskMaker(runner):
    def makeTask(var ident :TaskType, priority :Int, var input, state,
                 handle):
        var link := taskList

        object task extends state:
            to getLink():
                return link

            to setLink(l):
                link := l

            to getIdent() :TaskType:
                return ident

            to setIdent(i :TaskType):
                ident := i

            to setLink(l):
                link := l

            to getPriority():
                return priority

            to addPacket(p, old):
                if (input == null):
                    input := p
                    state.setPacketPending()
                    if (priority > old.getPriority()):
                        return task
                else:
                    p.appendTo(input)
                return old

            to runTask():
                def msg := if (state.isWaitingWithPacket()) {
                    def next := input
                    input := next.getLink()
                    if (input == null) {
                        state.running()
                    } else {
                        state.packetPending()
                    }
                    next
                }

                return runner(task, msg, handle)

            to waitTask():
                state.setTaskWaiting()
                return task

            to hold():
                holdCount += 1
                state.setTaskHolding()
                return link

            to release(i :TaskType):
                def t := findtcb(i)
                t.clearTaskHolding()
                if (t.getPriority() > priority):
                    return t
                else:
                    return task

            to qpkt(pkt):
                def t := findtcb(pkt.getIdent())
                qpktCount += 1
                pkt.setLink(null)
                pkt.setIdent(ident)
                return t.addPacket(pkt, task)

        taskList := task 
        taskTab with= (ident, task)

        return task

    # XXX return def ...
    return makeTask


def runDeviceTask(task, var packet, r):
    if (packet == null):
        packet := r["pending"]
        if (packet == null):
            return task.waitTask()
        else:
            r["pending"] := null
            return task.qpkt(packet)
    else:
        r["pending"] := packet
        trace(`${packet.getDatum()}`[0])
        return task.hold()

def makeDeviceTask := makeTaskMaker(runDeviceTask)


def runHandlerTask(task, packet, r):
    if (packet != null):
        if (packet.getKind() == KWORK):
            r["workIn"] := packet.appendTo(r["workIn"])
        else:
            r["deviceIn"] := packet.appendTo(r["deviceIn"])

    def work := r["workIn"]
    if (work == null):
        return task.waitTask()

    def count := work.getDatum()
    if (count >= BUFSIZE):
        r["workIn"] := work.getLink()
        return task.qpkt(work)

    def dev := r["deviceIn"]
    if (dev == null):
        return task.waitTask()

    r["deviceIn"] := dev.getLink()
    dev.setDatum(work.getData(count))
    work.setDatum(count + 1)
    return task.qpkt(dev)

def makeHandlerTask := makeTaskMaker(runHandlerTask)


def runIdleTask(task, packet, r):
    r["count"] -= 1
    if (r["count"] == 0):
        return task.hold()
    else if ((r["control"] & 1) == 0):
        r["control"] //= 2
        return task.release(DEVA)
    else:
        r["control"] := (r["control"] // 2) ^ 0xd008
        return task.release(DEVB)

def makeIdleTask := makeTaskMaker(runIdleTask)


def runWorkTask(task, packet, r):
    if (packet == null):
        return task.waitTask()

    def dest := if (r["destination"] == HANDLERA) {
        HANDLERB
    } else {
        HANDLERA
    }

    r["destination"] := dest
    packet.setIdent(dest)
    packet.setDatum(0)

    for i in 0..!BUFSIZE:
        r["count"] += 1
        if (r["count"] > 26):
            r["count"] := 1
        packet.setData(i, 'A'.asInteger() + r["count"] - 1)

    return task.qpkt(packet)

def makeWorkTask := makeTaskMaker(runWorkTask)


def schedule():
    var t := taskList
    while (t != null):
        # traceln(`tcb = ${t.getIdent()}`)

        if (t.isTaskHoldingOrWaiting()):
            # traceln(`holding or waiting $t`)
            t := t.getLink()
        else:
            trace('0' + t.getIdent().asInteger())
            t := t.runTask()


def runRichards() :Bool:
    var wkq := null

    holdCount := 0
    qpktCount := 0

    makeIdleTask(IDLE, 1, null, makeTaskState().running(),
                 makeIdleTaskRecord())

    wkq := makePacket(null, BLANK, KWORK)
    wkq := makePacket(wkq, BLANK, KWORK)
    makeWorkTask(WORK, 1000, wkq, makeTaskState().waitingWithPacket(),
                 makeWorkerTaskRecord())

    wkq := makePacket(null, DEVA, KDEV)
    wkq := makePacket(wkq, DEVA, KDEV)
    wkq := makePacket(wkq, DEVA, KDEV)
    makeHandlerTask(HANDLERA, 2000, wkq, makeTaskState().waitingWithPacket(),
                    makeHandlerTaskRecord())

    wkq := makePacket(null, DEVB, KDEV)
    wkq := makePacket(wkq, DEVB, KDEV)
    wkq := makePacket(wkq, DEVB, KDEV)
    makeHandlerTask(HANDLERB, 3000, wkq, makeTaskState().waitingWithPacket(),
                    makeHandlerTaskRecord())

    makeDeviceTask(DEVA, 4000, null, makeTaskState().waiting(),
                   makeDeviceTaskRecord())
    makeDeviceTask(DEVB, 5000, null, makeTaskState().waiting(),
                   makeDeviceTaskRecord())
    
    schedule()

    return holdCount == 9297 & qpktCount == 23246

bench(runRichards, "richards")
