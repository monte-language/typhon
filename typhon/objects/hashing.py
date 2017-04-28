"""
Simple fast universal hashes.
"""

from rpython.rlib.rarithmetic import intmask

def hashInt(a, x):
    """
    Hash `x`.

    `a` must be odd and at least 3. It should be a hefty number.
    """

    return intmask(a * x)

def hashList(a, p, x, xs):
    """
    Hash `xs` with starting value `x` on prime modulus `p`.

    The formal parameter `a` must be smaller than `p`.
    """

    for y in xs:
        x = intmask((a * x) ^ y) % p
    return x
