========
TyphonVM
========

A virtual machine for Kernel-E.

Scopes
======

Typhon maintains a stack of scopes in its environment, creating new scopes as
appropriate and discarding them when done. Rather than E's single universal
scope, Typhon separates the universal scope into the **basic** scope and
**fancy** scope. The basic scope contains objects which are DeepFrozen and
Functional; all other universal objects are in the fancy scope.
