import "bench" =~ [=> bench]
exports ()

def switchBench(i):
    return switch (i):
        match ==0:
            0
        match ==1:
            1
        match ==2:
            2
        match ==3:
            3
        match ==4:
            4
        match ==5:
            5

for i in (0..5):
    bench(fn { switchBench(i) }, `Switch-expr case $i`)

def ifBench(i):
    return if (i == 0):
        0
    else if (i == 1):
        1
    else if (i == 2):
        2
    else if (i == 3):
        3
    else if (i == 4):
        4
    else if (i == 5):
        5

for i in (0..5):
    bench(fn { ifBench(i) }, `If-expr case $i`)


def sameEverIntBench(i):
    return i == i

bench(fn { for i in (0..10) { sameEverIntBench(i) } }, `.sameEver/2 Int`)

def asBigAsIntBench(i):
    return i <=> i

bench(fn { for i in (0..10) { asBigAsIntBench(i) } }, `.asBigAs/2 Int`)
