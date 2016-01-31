import "bench" =~ [=> bench]
import "lib/entropy/pcg" =~ [=> makePCG]
import "lib/entropy/entropy" =~ [=> makeEntropy]
exports ()
c
def e := makeEntropy(makePCG(0x12345678, 0))
bench(e.nextBool, "entropy nextBool")
bench(fn {e.nextInt(4096)}, "entropy nextInt (best case)")
bench(fn {e.nextInt(4097)}, "entropy nextInt (worst case)")
bench(e.nextDouble, "entropy nextDouble")
