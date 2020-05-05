#include "Cello.h"

/*
 * The most important convention:
 *   Monte objects use Call to pass a Tuple of [verb, args, namedArgs].
 */

var Refused = CelloEmpty(Refused);

struct ConstList {
    var l;
};

void ConstList_New(var self, var args) {
    struct ConstList *cl = self;
    cl->l = get(args, $I(0));
}

var ConstList_Call(var self, var args) {
    struct ConstList *cl = self;
    var verb = get(args, $I(0));
    if (neq(verb, $S("size"))) {
        throw(Refused, "doesn't respond to verb %$", verb);
    }
    return new(Int, $I(len(cl->l)));
}

var ConstList = Cello(ConstList,
    Instance(New, ConstList_New, NULL),
    Instance(Call, ConstList_Call));

var makeList(var args) {
    print("makeList(%$)", args);
    var verb = get(args, $I(0));
    if (neq(verb, $S("run"))) {
        throw(Refused, "doesn't respond to verb %$", verb);
    }
    return new(ConstList, get(args, $I(1)));
}
