exports (main)

def main(=> bench, => unittest) as DeepFrozen:
    def [=> makePCG] | _ := ::"import"("lib/entropy/pcg", [=> unittest])
    def [=> makeEntropy] | _ := ::"import"("lib/entropy/entropy", [=> unittest])

    def e := makeEntropy(makePCG(0x12345678, 0))
    bench(e.nextBool, "entropy nextBool")
    bench(fn {e.nextInt(4096)}, "entropy nextInt (best case)")
    bench(fn {e.nextInt(4097)}, "entropy nextInt (worst case)")
    bench(e.nextDouble, "entropy nextDouble")
    return 0
