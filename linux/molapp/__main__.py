"""Entry point: `python3 -m molapp`."""

from __future__ import annotations

import sys


def main(argv: list[str] | None = None) -> int:
    from .webview import ViewerAssetsMissing, viewer_html_path

    try:
        # Resolved up front, not lazily inside the window: GTK catches exceptions raised in signal
        # handlers, so a missing viewer.html would otherwise print a traceback from inside
        # `do_activate` and leave an empty window running.
        viewer_html_path()
    except ViewerAssetsMissing as error:
        print(f"molapp: {error}", file=sys.stderr)
        return 1

    from .window import MolAppApplication

    return MolAppApplication().run(argv if argv is not None else sys.argv)


if __name__ == "__main__":
    raise SystemExit(main())
