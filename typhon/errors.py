class Ejecting(Exception):
    """
    An ejector is currently being used.
    """

    def __init__(self, ejector, value):
        self.ejector = ejector
        self.value = value



class UserException(Exception):
    """
    An error occurred in user code.
    """

    def error(self):
        return u"Error"


class Refused(UserException):
    """
    An object refused to accept a message passed to it.
    """

    def __init__(self, verb, args):
        self.verb = verb
        self.args = args

    def error(self):
        args = u", ".join([arg.repr().decode("utf-8") for arg in self.args])
        return u"Message refused: (%s, [%s])" % (self.verb, args)
