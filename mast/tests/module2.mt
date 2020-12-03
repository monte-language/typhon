import "tests/module1" =~ [=> sentinel1]
exports (sentinel2)

# See tests/modules

def sentinel2 :DeepFrozen := sentinel1
