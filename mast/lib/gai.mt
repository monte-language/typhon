exports (makeGAI)

def makeGAI(addrs :List) as DeepFrozen:
    return object GAI: # as DeepFrozen:
        "Management of address objects."

        to TCP4() :List:
            return [for addr in (addrs)
                    ? (addr.getFamily() == "INET" &&
                       addr.getSocketType() == "stream")
                    addr]

        to TCP6() :List:
            return [for addr in (addrs)
                    ? (addr.getFamily() == "INET6" &&
                       addr.getSocketType() == "stream")
                    addr]
