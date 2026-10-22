import os
from PIL import Image, ImageEnhance, ImageOps

def process_image_for_kindle(input_path: str, output_path: str, target_width: int = 1072, target_height: int = 1448) -> str:
    """
    Optimizes a photo specifically for Kindle e-ink display:
    1. Fits image into Kindle dimensions preserving aspect ratio with clean white letterboxing.
    2. Boosts contrast and edge sharpness for e-ink.
    3. Applies Floyd-Steinberg dithering for crisp monochrome rendering.
    """
    with Image.open(input_path) as img:
        img = img.convert("RGB")

        # 1. Aspect Ratio Preserving Resize
        img_w, img_h = img.size
        img_ratio = img_w / img_h
        target_ratio = target_width / target_height

        if img_ratio > target_ratio:
            new_w = target_width
            new_h = int(target_width / img_ratio)
        else:
            new_h = target_height
            new_w = int(target_height * img_ratio)

        resized = img.resize((new_w, new_h), Image.Resampling.LANCZOS)

        # 2. Sharpening & Contrast Tuning for E-Ink
        enhancer = ImageEnhance.Contrast(resized)
        boosted = enhancer.enhance(1.25)

        sharpener = ImageEnhance.Sharpness(boosted)
        crisp = sharpener.enhance(1.4)

        # Convert to grayscale and auto-stretch levels
        gray = crisp.convert("L")
        gray = ImageOps.autocontrast(gray, cutoff=1)

        # 3. Canvas Matte (Clean white borders)
        canvas = Image.new("L", (target_width, target_height), 255)
        paste_x = (target_width - new_w) // 2
        paste_y = (target_height - new_h) // 2
        canvas.paste(gray, (paste_x, paste_y))

        # 4. Floyd-Steinberg Dithering
        dithered = canvas.convert("1", dither=Image.Dither.FLOYDSTEINBERG)

        os.makedirs(os.path.dirname(output_path), exist_ok=True)
        dithered.save(output_path, "PNG", optimize=True)
        return output_path
