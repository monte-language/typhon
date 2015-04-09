======
Typhon
======

Typhon is a virtual machine for Monte. It loads and executes Kernel-Monte from
Monte AST files.

How To Monte
============

Typhon operates in both untranslated and translated modes, with an optional
JIT. Regardless of mode of operation, you'll need some dependencies (Twisted
and RPython), so create a virtualenv::

    $ virtualenv local-typhon -p pypy
    $ . local-typhon/bin/activate
    $ pip install -r requirements.txt

If you don't have PyPy, you can leave off ``-p pypy``, but be warned that this
will increase run times. Once that's done, Typhon can be run untranslated::

    $ python main.py your/awesome/script.ty

Translation is done via the RPython toolchain::

    $ python -m rpython -O2 main

The JIT can be enabled with a switch::

    $ python -m rpython -Ojit main

The resulting executable is immediately usable for any scripts that don't use
prelude features::

    $ ./main-c your/awesome/script.ty

Note that translation is not cheap. It will require approximately 0.5GiB
memory and 2min CPU time on a 64-bit x86 system to translate a non-JIT Typhon
executable, or 1GiB memory and 9min CPU time with the JIT enabled.

MAST Prelude
============

Without a prelude, Typhon doesn't do much. Most Monte applications have a
reasonable expectation of certain non-kernel features, which are implemented
in Monte via a prelude and library.

Edit ``mast/Makefile`` to point ``MONTE`` to the location of your `reference
Monte`_ checkout, and ``MONTE_VENV`` to the virtualenv in which you've
installed Monte's ``requirements.txt``. 

To build the MAST library::

    $ make -C mast

You'll need to have a reference Monte nearby for the actual build, just like
with other Monte code running on Typhon.

Then, you can use the prelude::

    $ ./main-c -l mast another/awesome/script.ty

Contributing
============

Contributions are welcome.

Unit tests are tested by Travis. You can run them yourself; I recommend the
Trial test runner::

    $ trial typhon

.. _reference Monte: https://github.com/monte-language/monte
