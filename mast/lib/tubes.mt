imports => unittest
exports (Pump, Unpauser, Fount, Drain, Tube,
         makeMapPump, makeSplitPump, makeStatefulPump,
         makeIterFount,
         makePureDrain,
         makePumpTube,
         chain)

def [=> Pump :DeepFrozen,
     => Unpauser :DeepFrozen,
     => Fount :DeepFrozen,
     => Drain :DeepFrozen,
     => Tube :DeepFrozen,
] := import("lib/tubes/itubes")

def [=> nullPump :DeepFrozen] := import("lib/tubes/nullPump")
def [=> makeMapPump :DeepFrozen] := import("lib/tubes/mapPump")
def [=> makeSplitPump :DeepFrozen,
] := import("lib/tubes/splitPump", [=> unittest])
def [=> makeStatefulPump :DeepFrozen] := import("lib/tubes/statefulPump")

def [=> makeIterFount :DeepFrozen] := import("lib/tubes/iterFount")

def [=> makePureDrain :DeepFrozen] := import("lib/tubes/pureDrain")

def [=> makePumpTube :DeepFrozen] := import("lib/tubes/pumpTube")

def [=> chain :DeepFrozen] := import("lib/tubes/chain")
