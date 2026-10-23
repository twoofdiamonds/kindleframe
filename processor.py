import os
from PIL import Image, ImageEnhance, ImageOps

def process_image_for_kindle(input_path: str, output_path: str, target_width: int = 600, target_height: int = 800) -> str:
    """
    Optimizes a photo specifically for Kindle 10th Gen Basic e-ink display (600x800):
    1. Crops and scales (aspect-fill center crop) to fill the screen edge-to-edge (no white letterboxing).
    2. Enhances contrast and edge sharpness for e-ink readability.
    3. Auto-adjusts black/white cutoff levels.
    4. Applies Floyd-Steinberg dithering for crisp 1-bit monochrome rendering.
    """
    with Image.open(input_path) as img:
        img = img.convert("RGB")

        # 1. Aspect-fill Center Crop to exact screen dimensions (600x800)
        cropped = ImageOps.fit(
            img,
            (target_width, target_height),
            method=Image.Resampling.LANCZOS,
            centering=(0.5, 0.5)
        )

        # 2. Sharpening & Contrast Tuning for E-Ink
        enhancer = ImageEnhance.Contrast(cropped)
        boosted = enhancer.enhance(1.30)

        sharpener = ImageEnhance.Sharpness(boosted)
        crisp = sharpener.enhance(1.45)

        # 3. Convert to grayscale and auto-stretch levels
        gray = crisp.convert("L")
        gray = ImageOps.autocontrast(gray, cutoff=1)

        # 4. Floyd-Steinberg Dithering
        dithered = gray.convert("1", dither=Image.Dither.FLOYDSTEINBERG)

        os.makedirs(os.path.dirname(output_path), exist_ok=True)
        dithered.save(output_path, "PNG", optimize=True)
        return output_path
