"""Build reviewed, transparent Forbidden Fruit runtime sprites."""

from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "tools/assets/forbidden_fruit_icon_snake_source.png"
ITEMS = ROOT / "mod/resources/gfx/items/collectibles"
EFFECTS = ROOT / "mod/resources/gfx/effects"


def remove_green(source: Image.Image) -> Image.Image:
    """Hard-key the generated green screen and despill antialiased edges."""
    out = source.convert("RGBA")
    pixels = out.load()
    for y in range(out.height):
        for x in range(out.width):
            r, g, b, _ = pixels[x, y]
            dominance = g - max(r, b)
            if g > 115 and dominance > 32:
                pixels[x, y] = (0, 0, 0, 0)
            elif dominance > 8:
                pixels[x, y] = (r, max(r, b), b, 255)
    return out


def make_icon() -> None:
    source = remove_green(Image.open(SOURCE))
    alpha = source.getchannel("A")
    bbox = alpha.getbbox()
    if not bbox:
        raise RuntimeError("Forbidden Fruit source became empty after chroma removal")
    cropped = source.crop(bbox)
    cropped.thumbnail((28, 28), Image.Resampling.NEAREST)
    out = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    out.alpha_composite(cropped, ((32 - cropped.width) // 2, (32 - cropped.height) // 2))
    ITEMS.mkdir(parents=True, exist_ok=True)
    out.save(ITEMS / "forbidden_fruit.png")


def sheet(frames: list[Image.Image], name: str) -> None:
    out = Image.new("RGBA", (frames[0].width * len(frames), frames[0].height), (0, 0, 0, 0))
    for index, frame in enumerate(frames):
        out.alpha_composite(frame, (index * frame.width, 0))
    EFFECTS.mkdir(parents=True, exist_ok=True)
    out.save(EFFECTS / name)


def make_vine() -> None:
    frames = []
    for phase in range(4):
        image = Image.new("RGBA", (96, 20), (0, 0, 0, 0))
        draw = ImageDraw.Draw(image)
        points = []
        for x in range(2, 95, 3):
            y = 10 + round(__import__("math").sin(x * 0.17 + phase * 0.65))
            points.append((x, y))
        draw.line(points, fill=(32, 7, 10, 205), width=2)
        draw.line(points, fill=(89 + phase * 3, 17, 23, 210), width=1)
        for x in range(17, 83, 24):
            y = points[(x - 2) // 3][1]
            direction = -1 if (x // 12 + phase) % 2 == 0 else 1
            draw.polygon(((x - 1, y), (x + 1, y + direction * 3), (x + 2, y)),
                         fill=(58, 7, 11, 210))
        frames.append(image)
    sheet(frames, "forbidden_fruit_vine.png")


def make_debuff() -> None:
    frames = []
    for quality in range(5):
        for phase in range(4):
            image = Image.new("RGBA", (48, 36), (0, 0, 0, 0))
            draw = ImageDraw.Draw(image)
            pulse = phase if phase <= 2 else 1
            alpha = 205 + pulse * 15
            draw.arc((12, 8, 36, 30), 205, 520, fill=(55, 7, 12, alpha), width=3)
            draw.arc((15, 11, 33, 27), 210, 515, fill=(140, 18, 27, alpha), width=2)
            draw.polygon(((21, 14), (23, 22), (25, 14)), fill=(226, 194, 162, 245))
            draw.polygon(((27, 14), (29, 22), (31, 14)), fill=(226, 194, 162, 245))
            for thorn in range(quality + 1):
                angle = 3.14159 * (0.85 + thorn / max(1, quality) * 1.3)
                import math
                x = 24 + round(math.cos(angle) * 14)
                y = 19 + round(math.sin(angle) * 11)
                tip_x = 24 + round(math.cos(angle) * (17 + quality))
                tip_y = 19 + round(math.sin(angle) * (14 + quality // 2))
                draw.line((x, y, tip_x, tip_y), fill=(93, 10, 18, alpha), width=2)
            start = 24 - (quality * 7 - 2) // 2
            for leaf in range(quality):
                x = start + leaf * 7
                y = 30 + (leaf % 2)
                draw.polygon(((x, y), (x + 3, y - 7), (x + 6, y - 1),
                              (x + 3, y + 2)), fill=(150, 18, 27, alpha),
                             outline=(45, 5, 9, alpha))
            frames.append(image)
    sheet(frames, "forbidden_fruit_debuff.png")


def make_leaves() -> None:
    frames = []
    for quality in range(5):
        image = Image.new("RGBA", (40, 14), (0, 0, 0, 0))
        draw = ImageDraw.Draw(image)
        start = 20 - (quality * 7 - 1) // 2
        for index in range(quality):
            x = start + index * 7
            lean = -1 if index % 2 == 0 else 1
            draw.line((x + 3, 11, x + 3 + lean, 13), fill=(45, 8, 11, 255), width=1)
            draw.polygon(((x + 3, 2), (x + 6, 6), (x + 5, 10),
                          (x + 3, 12), (x + 1, 9), (x, 6)),
                         fill=(43, 7, 11, 255))
            draw.polygon(((x + 3, 3), (x + 5, 6), (x + 4, 9),
                          (x + 3, 10), (x + 2, 8), (x + 1, 6)),
                         fill=(125, 19, 27, 255))
            draw.line((x + 3, 4, x + 3, 10), fill=(195, 47, 46, 230), width=1)
        frames.append(image)
    sheet(frames, "forbidden_fruit_leaves.png")


if __name__ == "__main__":
    make_icon()
    make_vine()
    make_debuff()
    make_leaves()
