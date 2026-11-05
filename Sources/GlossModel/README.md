# GlossModel

Reads what the docs say as contracts, and the types as a graph of which uses which. It holds what the docs say, never whether they follow the house style.

## Overview

``Interface`` builds a ``Contract`` for every declaration and the ``Graph`` between types. ``InterfaceDiff`` compares two interfaces, moves included, and ``StoryCoverage`` checks that a branch's ``ChangeStory`` gives every change a reason. ``Reason`` and ``ChangeCommits`` say why, from the docs and from the commits.

## Topics

### The interface

- ``Interface``
- ``Contract``
- ``Graph``
- ``Reason``

### Changes

- ``InterfaceDiff``
- ``ChangeCommits``

### Stories

- ``ChangeStory``
- ``StoryCoverage``
