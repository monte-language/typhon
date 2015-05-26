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

(
    DUP, ROT, POP, SWAP,
    ASSIGN_GLOBAL, ASSIGN_FRAME, ASSIGN_LOCAL,
    BIND, BINDFINALSLOT, BINDVARSLOT,
    SLOT_GLOBAL, SLOT_FRAME, SLOT_LOCAL,
    NOUN_GLOBAL, NOUN_FRAME, NOUN_LOCAL,
    BINDING_GLOBAL,  BINDING_FRAME, BINDING_LOCAL,
    LIST_PATT,
    LITERAL,
    BINDOBJECT, SCOPE,
    EJECTOR, TRY, UNWIND, END_HANDLER,
    BRANCH, CALL, JUMP,
) = range(30)

ops = {
    "DUP": DUP,
    "ROT": ROT,
    "POP": POP,
    "SWAP": SWAP,
    "ASSIGN_GLOBAL": ASSIGN_GLOBAL,
    "ASSIGN_FRAME": ASSIGN_FRAME,
    "ASSIGN_LOCAL": ASSIGN_LOCAL,
    "BIND": BIND,
    "BINDFINALSLOT": BINDFINALSLOT,
    "BINDVARSLOT": BINDVARSLOT,
    "SLOT_GLOBAL": SLOT_GLOBAL,
    "SLOT_FRAME": SLOT_FRAME,
    "SLOT_LOCAL": SLOT_LOCAL,
    "NOUN_GLOBAL": NOUN_GLOBAL,
    "NOUN_FRAME": NOUN_FRAME,
    "NOUN_LOCAL": NOUN_LOCAL,
    "BINDING_GLOBAL": BINDING_GLOBAL,
    "BINDING_FRAME": BINDING_FRAME,
    "BINDING_LOCAL": BINDING_LOCAL,
    "LIST_PATT": LIST_PATT,
    "LITERAL": LITERAL,
    "BINDOBJECT": BINDOBJECT,
    "SCOPE": SCOPE,
    "EJECTOR": EJECTOR,
    "TRY": TRY,
    "UNWIND": UNWIND,
    "END_HANDLER": END_HANDLER,
    "BRANCH": BRANCH,
    "CALL": CALL,
    "JUMP": JUMP,
}

reverseOps = [""] * 30
for k, v in ops.iteritems():
    reverseOps[v] = k
