# Contributing

Fixes from other people are welcome as pull requests. Every patch here is
carried for six Mesa versions, and only real hardware shows whether a video
fix works, so a pull request should:

- add the patch to every series under `patches/`, or say which ones it does
  not apply to and why;
- say which GPU it was tested on, and how;
- keep its author as the author of the patch.

We review it and test what we can on a GeForce GT 240M (VP4), but we don't
port or maintain patches for hardware we don't have. A fix that belongs in
Mesa should also go to Mesa as a merge request: this repository only carries
it until Ubuntu ships it.
