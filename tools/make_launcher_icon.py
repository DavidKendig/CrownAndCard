# SPDX-License-Identifier: AGPL-3.0-or-later
"""Package the generated PNG master into the launcher's multi-resolution ICO.

Requires Pillow. Usage: python tools/make_launcher_icon.py
This only converts/resizes the artwork; it does not regenerate the design.
"""
import pathlib

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
ASSETS = ROOT / "launcher" / "assets"
SIZES = (16, 20, 24, 32, 40, 48, 64, 96, 128, 256)


def main():
    with Image.open(ASSETS / "launcher-icon.png") as source:
        source = source.convert("RGBA")
        bounds = source.getchannel("A").getbbox()
        if bounds is None:
            raise ValueError("The icon master is transparent.")
        artwork = source.crop(bounds)
        # Square padding keeps the complete crown visible in Windows icon slots.
        side = max(artwork.size)
        canvas = Image.new("RGBA", (side, side))
        canvas.paste(artwork, ((side - artwork.width) // 2, (side - artwork.height) // 2))
        images = []
        for size in SIZES:
            image = Image.new("RGBA", (size, size))
            fitted = canvas.resize((size - 2, size - 2), Image.Resampling.LANCZOS)
            image.paste(fitted, (1, 1))
            images.append(image)
        out = ASSETS / "launcher.ico"
        images[-1].save(out, format="ICO", sizes=[(s, s) for s in SIZES], append_images=images[:-1])
    with Image.open(out) as result:
        assert result.ico.sizes() == {(s, s) for s in SIZES}
    print(f"Wrote {out.relative_to(ROOT)} ({len(SIZES)} sizes)")


if __name__ == "__main__":
    main()
