import "tests/module1" =~ [=> sentinel1]
exports (sentinel3)

# See tests/modules

def sentinel3 :DeepFrozen := sentinel1
