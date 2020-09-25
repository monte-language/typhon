"""
DNS getaddrinfo().
"""

from rpython.rlib import _rsocket_rffi as s
from rpython.rtyper.lltypesystem.lltype import nullptr
from rpython.rtyper.lltypesystem.rffi import getintfield

from typhon import ruv
from typhon.atoms import getAtom
from typhon.autohelp import autohelp, method
from typhon.futures import resolve, smash
from typhon.macros import macros, io
from typhon.objects.collections.lists import wrapList
from typhon.objects.data import bytesToString, unwrapBytes, StrObject
from typhon.objects.refs import makePromise
from typhon.objects.root import Object, runnable
from typhon.vats import currentVat


RUN_2 = getAtom(u"run", 2)


socktypes = {
    s.SOCK_DGRAM: u"datagram",
    s.SOCK_RAW: u"raw",
    s.SOCK_RDM: u"reliable datagram",
    s.SOCK_SEQPACKET: u"packet",
    s.SOCK_STREAM: u"stream",
}


@autohelp
class AddrInfo(Object):

    _immutable_fields_ = "family", "socktype", "addr"

    @method("Bytes")
    def getAddress(self):
        return self.addr

    @method("Str")
    def getFamily(self):
        return self.family

    @method("Str")
    def getSocketType(self):
        return self.socktype


@autohelp
class IP4AddrInfo(AddrInfo):
    """
    Information about an IPv4 network address.
    """

    _immutable_fields_ = "flags", "socktype", "protocol", "addr"

    family = u"INET"

    def __init__(self, ai):
        self.flags = getintfield(ai, "c_ai_flags")
        self.socktype = socktypes.get(getintfield(ai, "c_ai_socktype"),
                                      u"unknown")
        # XXX getprotoent(3)
        self.protocol = getintfield(ai, "c_ai_protocol")
        self.addr = ruv.IP4Name(ai.c_ai_addr)

    def toString(self):
        return u"IP4AddrInfo(%s, %s, %d, %d)" % (bytesToString(self.addr),
                                                 self.socktype, self.protocol,
                                                 self.flags)


@autohelp
class IP6AddrInfo(AddrInfo):
    """
    Information about an IPv6 network address.
    """

    _immutable_fields_ = "flags", "socktype", "protocol", "addr"

    family = u"INET6"

    def __init__(self, ai):
        self.flags = getintfield(ai, "c_ai_flags")
        self.socktype = socktypes.get(getintfield(ai, "c_ai_socktype"),
                                      u"unknown")
        # XXX getprotoent(3)
        self.protocol = getintfield(ai, "c_ai_protocol")
        self.addr = ruv.IP6Name(ai.c_ai_addr)

    def toString(self):
        return u"IP6AddrInfo(%s, %s, %d, %d)" % (bytesToString(self.addr),
                                                 self.socktype, self.protocol,
                                                 self.flags)


def walkAI(ai):
    # Does this need to move into ruv? No, while it touches ruv objects, it is
    # traversing them and packing them into Monte objects. We want to keep
    # Monte out of ruv, so this sort of function should live here. ~ C.
    rv = []
    while ai:
        family = getintfield(ai, "c_ai_family")
        if family == s.AF_INET:
            rv.append(IP4AddrInfo(ai))
        elif family == s.AF_INET6:
            rv.append(IP6AddrInfo(ai))
        else:
            print "Skipping family", family, "for", ai
        ai = ai.c_ai_next
    return rv


@runnable(RUN_2)
def getAddrInfo(node, service):
    node = unwrapBytes(node)
    service = unwrapBytes(service)
    vat = currentVat.get()
    p, r = makePromise()
    emptyAI = nullptr(ruv.s.addrinfo)
    with io:
        ai = emptyAI
        try:
            ai = ruv.magic_getAddrInfo(vat, node, service)
        except object as err:
            smash(r, StrObject(u"libuv error: %s" % err))
        else:
            resolve(r, wrapList(walkAI(ai)[:]))
    return p
