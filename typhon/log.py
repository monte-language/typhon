"""
Simple tagged logger.
"""


class Logger(object):
    """
    A logger which uses context tags to determine whether an event is
    loggable.
    """

    def __init__(self):
        self.tags = {}

    def log(self, tags, message):
        for tag in tags:
            if tag in self.tags:
                self.write(tags, message)
                return

    def write(self, tags, message):
        tagString = "(%s)" % ":".join(tags)
        print "Log:", tagString, message.encode("utf-8")


logger = Logger()
log = logger.log
