import os
from PIL import Image, ImageEnhance, ImageOps

def process_image_for_kindle(input_path: str, output_path: str, target_width: int = 600, target_height: int = 800) -> str:
    """
    Optimizes a photo for Kindle 10th Gen Basic e-ink screensaver:
    1. Crops and scales (aspect-fill center crop) to fill 600x800 edge-to-edge.
    2. Subtle contrast and sharpness tuning (avoids harsh grain / noise).
    3. Outputs smooth 8-bit Grayscale (Mode 'L') so the Kindle's 16-shade e-ink
       controller renders smooth photographic tones without 1-bit dithering noise.
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

        # 2. Gentle contrast punch suited for e-ink (without blowing out highlights)
        enhancer = ImageEnhance.Contrast(cropped)
        boosted = enhancer.enhance(1.10)

        # 3. Subtle sharpness for crisp edges (avoids creating speckle grain)
        sharpener = ImageEnhance.Sharpness(boosted)
        crisp = sharpener.enhance(1.15)

        # 4. Convert to smooth 8-bit Grayscale
        gray = crisp.convert("L")
        gray = ImageOps.autocontrast(gray, cutoff=0.5)

        # Save as smooth 8-bit Grayscale PNG (NO 1-bit Floyd-Steinberg grain)
        os.makedirs(os.path.dirname(output_path), exist_ok=True)
        gray.save(output_path, "PNG", optimize=True)
        return output_path
