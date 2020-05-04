#include "Cello.h"

/*
 * The most important convention:
 *   Monte objects use Call to pass a Tuple of [verb, args, namedArgs].
 */

var Monte = CelloEmpty(Monte);

var Refused = CelloEmpty(Refused);

var makeList(var args) {
    print("makeList(%$)", args);
    var verb = get(args, $I(0));
    if (neq(verb, $S("run"))) {
        throw(Refused, "doesn't respond to verb %$", verb);
    }
    /* XXX wrap */
    return get(args, $I(1));
}
