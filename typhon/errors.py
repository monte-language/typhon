class Ejecting(Exception):
    """
    An ejector is currently being used.
    """

    def __init__(self, ejector, value):
        self.ejector = ejector
        self.value = value


class Refused(Exception):
    """
    An object refused to accept a message passed to it.
    """

    def __init__(self, verb, args):
        self.verb = verb
        self.args = verb, args
