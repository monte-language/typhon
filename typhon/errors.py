class Ejecting(Exception):
    """
    An ejector is currently being used.
    """

    def __init__(self, ejector, value):
        self.ejector = ejector
        self.value = value
