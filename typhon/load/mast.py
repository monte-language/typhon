from typhon.load.nano import loadMASTBytes as realLoad
from typhon.nano.mast import BuildKernelNodes


def loadMASTBytes(bs, noisy=False):
    return BuildKernelNodes().visitExpr(realLoad(bs, noisy))


def loadMASTHandle(handle, noisy=False):
    return loadMASTBytes(handle.read(), noisy)


def loadMAST(path, noisy=False):
    with open(path, "rb") as handle:
        return loadMASTHandle(handle, noisy)
