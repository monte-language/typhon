#include "Cello.h"

/*
 * The most important convention:
 *   Monte objects use Call to pass a Tuple of [verb, args, namedArgs].
 */

var Refused = CelloEmpty(Refused);

/* FinalSlots are a pair of a value and a guard. */

struct FinalSlot {
    var value;
    var guard;
};

void FinalSlot_New(var self, var args) {
    struct FinalSlot *fs = self;
    fs->value = get(args, $I(0));
    fs->guard = get(args, $I(1));
}

var FinalSlot_Call(var self, var args) {
    struct FinalSlot *fs = self;
    var verb = get(args, $I(0));
    if (eq(verb, $S("get"))) {
        return fs->value;
    } else if (eq(verb, $S("getGuard"))) {
        return fs->guard;
    }
    throw(Refused, "%$ doesn't respond to verb %$", self, verb);
}

var FinalSlot = Cello(FinalSlot,
    Instance(New, FinalSlot_New, NULL),
    Instance(Call, FinalSlot_Call));

/* ConstLists are merely wrappers around Cello lists. */

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
        throw(Refused, "%$ doesn't respond to verb %$", self, verb);
    }
    return new(Int, $I(len(cl->l)));
}

var ConstList = Cello(ConstList,
    Instance(New, ConstList_New, NULL),
    Instance(Call, ConstList_Call));

var nullObj(var args) {
    var verb = get(args, $I(0));
    throw(Refused, "%$ doesn't respond to verb %$", nullObj, verb);
}

var trueObj(var args) {
    var verb = get(args, $I(0));
    throw(Refused, "%$ doesn't respond to verb %$", trueObj, verb);
}

var falseObj(var args) {
    var verb = get(args, $I(0));
    throw(Refused, "%$ doesn't respond to verb %$", falseObj, verb);
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
        throw(Refused, "%$ doesn't respond to verb %$", makeList, verb);
    }
    return new(ConstList, get(args, $I(1)));
}

var guardInt(var args) {
    print("guardInt(%$)", args);
    var verb = get(args, $I(0));
    if (neq(verb, $S("coerce"))) {
        throw(Refused, "%$ doesn't respond to verb %$", guardInt, verb);
    }
    var specimen = get(get(args, $I(1)), $I(0));
    /* XXX typechecking */
    return specimen;
}

var guardAny(var args) {
    print("guardAny(%$)", args);
    var verb = get(args, $I(0));
    if (neq(verb, $S("coerce"))) {
        throw(Refused, "%$ doesn't respond to verb %$", guardAny, verb);
    }
    var specimen = get(get(args, $I(1)), $I(0));
    return specimen;
}
