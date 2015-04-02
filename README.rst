======
Typhon
======

Typhon is a virtual machine for Monte. It loads and executes Kernel-Monte from
Monte AST files.

How To Monte
============

Typhon operates in both untranslated and translated modes, with an optional
JIT. Regardless of mode of operation, you will need RPython. Since RPython
doesn't come on its own, you will need to grab a `PyPy source tarball`_ and add
its contents to your ``PYTHONPATH`` environment variable::

    $ wget https://bitbucket.org/pypy/pypy/downloads/pypy-2.5.1-src.tar.bz2
    $ tar -xvf pypy-2.5.1-src.tar.bz2
    $ export PYTHONPATH=path/to/pypy-2.5.1-src:.

Note that simply installing pypy from your system package manager will
probably not work. If RPython is unavailable, attempting to run Typhon will
result in an error like::

    RPython traceback:
        File "implement.c", line 3285, in entryPoint
        ...
    Aborted (core dumped)

Once you have a pypy with rpython in your ``PYTHONPATH``, Typhon can be run
untranslated::

    $ python main.py your/awesome/script.ty

Translation is done via the RPython toolchain::

    $ path/to/your/pypy/rpython/bin/rpython main

The JIT can be enabled with a switch::

    $ path/to/your/pypy/rpython/bin/rpython -Ojit main
 
The resulting executable is immediately usable for any scripts that don't use
prelude features::

    $ ./main-c your/awesome/script.ty

Note that translation is not cheap. It will require approximately 0.5GiB
memory and 2min CPU time on a 64-bit x86 system to translate a non-JIT Typhon
executable, or 1GiB memory and 8min CPU time with the JIT enabled.

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

.. _PyPy source tarball: https://bitbucket.org/pypy/pypy/downloads/pypy-2.5.1-src.tar.bz2
.. _reference Monte: https://github.com/monte-language/monte
