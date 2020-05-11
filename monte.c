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

struct True {};
struct False {};

var trueObj(var args) {
    var verb = get(args, $I(0));
    throw(Refused, "doesn't respond to verb %$", verb);
}

var falseObj(var args) {
    var verb = get(args, $I(0));
    throw(Refused, "doesn't respond to verb %$", verb);
}

/* Return whether a var is Monte's true or false. Throw if it's neither. */
bool isTrue(var b) {
    if (eq(b, $(Function, trueObj))) {
        return true;
    } else if (eq(b, $(Function, falseObj))) {
        return false;
    } else {
        throw(TypeError, "%$ !~ _ :Bool", b);
    }
}

var makeList(var args) {
    print("makeList(%$)", args);
    var verb = get(args, $I(0));
    if (neq(verb, $S("run"))) {
        throw(Refused, "doesn't respond to verb %$", verb);
    }
    return new(ConstList, get(args, $I(1)));
}
