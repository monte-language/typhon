# Copyright (C) 2014 Google Inc. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may not
# use this file except in compliance with the License. You may obtain a copy
# of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations
# under the License.


class PrettyWriter(object):
    pass


class LineWriter(PrettyWriter):
    """
    A very simple indentation-tracking line writer.

    Inspired by PythonWriter, TextWriter, and all other very simple
    indentation-tracking line writers.
    """

    depth = 0
    midline = False

    def __init__(self, writer):
        self._writer = writer

    def indent(self):
        indented = LineWriter(self._writer)
        indented.depth = self.depth + 2
        return indented

    def _writeIndent(self):
        self._writer.write(" " * self.depth)

    def write(self, data):
        if not self.midline:
            self.midline = True
            self._writeIndent()
        self._writer.write(data)

    def writeLine(self, data):
        self.write(data)
        self.write("\n")
        self.midline = False


class OneLine(PrettyWriter):
    """
    A single-line pretty writer.

    Stores exactly one line in an internal buffer. Meant for traceback
    prettification.
    """

    finished = False

    def __init__(self):
        self._pieces = []

    def indent(self):
        return self

    def write(self, data):
        if not self.finished:
            self._pieces.append(data)

    def writeLine(self, data):
        self.write(data)
        self.finished = True

    def getLine(self):
        return "".join(self._pieces)


class Buffer(object):
    def __init__(self):
        self._buf = []

    def write(self, data):
        self._buf.append(data)

    def get(self):
        return "".join(self._buf)
