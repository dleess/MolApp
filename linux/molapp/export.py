"""Export encoders. Mol* hands us a PNG data URL from the WebGL viewport; these re-encode it into
the requested container, the same five the other shells offer.

Port of `export.dart`; Pillow stands in for the `image` + `pdf` Dart packages.
"""

from __future__ import annotations

import base64
import binascii
import io

from PIL import Image

from .models import ExportFormat


class ExportError(Exception):
    pass


def bytes_from_data_url(data_url: str) -> bytes | None:
    """`data:image/png;base64,...` → raw bytes."""
    comma = data_url.find(",")
    if comma < 0:
        return None
    try:
        return base64.b64decode(data_url[comma + 1:], validate=True)
    except (binascii.Error, ValueError):
        return None


def encode_export(png: bytes, format: ExportFormat) -> bytes:
    """The PNG from JS is the source of truth; re-encode it into the requested container."""
    if format is ExportFormat.png:
        return png
    if format is ExportFormat.svg:
        return _svg_wrapping(png)

    image = _decode(png)
    buffer = io.BytesIO()
    if format is ExportFormat.jpeg:
        # JPEG has no alpha channel; the viewport is opaque, so flattening onto its own background
        # is lossless in practice and avoids Pillow refusing the RGBA input outright.
        image.convert("RGB").save(buffer, "JPEG", quality=95)
    elif format is ExportFormat.gif:
        # Single frame: the viewport is a still, matching the native apps' GIF export.
        image.convert("P", palette=Image.Palette.ADAPTIVE).save(buffer, "GIF")
    elif format is ExportFormat.pdf:
        image.convert("RGB").save(buffer, "PDF", resolution=72.0)
    else:  # pragma: no cover - the enum is closed
        raise ExportError(f"Unsupported export format: {format}")
    return buffer.getvalue()


def _decode(png: bytes) -> Image.Image:
    try:
        image = Image.open(io.BytesIO(png))
        image.load()
    except Exception as error:
        raise ExportError("Could not decode the captured image.") from error
    return image


def _svg_wrapping(png: bytes) -> bytes:
    """A WebGL viewport is raster, so a true vector SVG is not possible — wrap the PNG in an SVG
    `<image>` so the .svg opens anywhere an SVG is expected.

    ponytail: raster inside vector is the known ceiling; a real vector export would have to come
    out of Mol* itself, not out of a screenshot.
    """
    image = _decode(png)
    width, height = image.size
    encoded = base64.b64encode(png).decode("ascii")
    svg = (
        '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" '
        f'width="{width}" height="{height}" viewBox="0 0 {width} {height}">\n'
        f'<image width="{width}" height="{height}" xlink:href="data:image/png;base64,{encoded}"/>\n'
        "</svg>\n"
    )
    return svg.encode("utf-8")
