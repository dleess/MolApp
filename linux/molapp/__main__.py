"""Entry point: `python3 -m molapp`."""

from __future__ import annotations

import sys


def main(argv: list[str] | None = None) -> int:
    from .window import MolAppApplication

    return MolAppApplication().run(argv if argv is not None else sys.argv)


if __name__ == "__main__":
    raise SystemExit(main())
