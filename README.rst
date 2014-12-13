======
Typhon
======

Typhon is a virtual machine for Monte. It loads and executes Kernel-Monte from
Monte AST files.

How To Monte
============

Typhon operates in both untranslated and translated modes, with an optional
JIT. Regardless of mode of operation, you will need RPython. Since RPython
doesn't come on its own, you will need to grab a PyPy source tarball and add
its contents to your ``PYTHONPATH`` environment variable::

    $ export PYTHONPATH=path/to/your/pypy:.

Once that's done, Typhon can be run untranslated::

    $ python main.py your/awesome/script.ty

Translation is done via the RPython toolchain::

    $ path/to/your/pypy/rpython/translator/goal/translate.py main

The JIT can be enabled with a switch::

    $ path/to/your/pypy/rpython/translator/goal/translate.py -Ojit main

The resulting executable is immediately usable::

    $ ./main-c your/awesome/script.ty

Note that translation is not cheap. It will require approximately 0.5GiB
memory and 2min CPU time on a 64-bit x86 system to translate a non-JIT Typhon
executable, or 1GiB memory and 8min CPU time with the JIT enabled.
