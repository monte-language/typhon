import "unittest" =~ [=> unittest :Any]
import "tests/module1" =~ [=> sentinel1]
import "tests/module2" =~ [=> sentinel2]
import "tests/module3" =~ [=> sentinel3]
exports ()

def testTriangleImports(assert):
    "
    Test that when one module re-exports something which it imported, then the
    resulting import triangle:

        A -> B
          .  |
           . v
             C

    Always observes the same object.
    "

    assert.equal(sentinel1, sentinel2)

def testDiamondImports(assert):
    "
    Test that when one module re-exports something which it imported, then the
    resulting import triangle:

             A
            / .
           /   .
          B     C
           .   /
            . /
             D

    Always observes the same object.
    "

    assert.equal(sentinel2, sentinel3)

unittest([
    testTriangleImports,
    testDiamondImports,
])
