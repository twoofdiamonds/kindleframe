import os
import json
import logging
import datetime
import urllib.request
import instaloader
from processor import process_image_for_kindle
from notifier import send_alert

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger("kindle_sync")

DOCS_DIR = "docs"
IMAGES_DIR = os.path.join(DOCS_DIR, "images")
STATE_FILE = os.path.join(DOCS_DIR, "posts_state.json")
MANIFEST_FILE = os.path.join(DOCS_DIR, "manifest.json")
INDEX_FILE = os.path.join(DOCS_DIR, "index.html")

def load_json(path, default):
    if os.path.exists(path):
        try:
            with open(path, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception as e:
            logger.error(f"Failed to read {path}: {e}")
    return default

def generate_html_gallery(active_posts, cycle_interval_min, target_user, last_sync):
    images_html = ""
    for post in active_posts:
        for img in post.get("images", []):
            images_html += f"""
            <div style="display:inline-block; margin: 12px; border: 1px solid #e2e8f0; border-radius: 8px; overflow: hidden; background: #fff; box-shadow: 0 4px 6px rgba(0,0,0,0.05);">
                <img src="images/{img}" style="width: 220px; height: auto; display: block;" />
                <div style="padding: 8px; font-size: 11px; text-align: center; color: #64748b;">Post: {post['shortcode']}<br/>{img}</div>
            </div>
            """
    if not images_html:
        images_html = "<p style='color: #94a3b8;'>No images synced yet.</p>"

    return f"""<!DOCTYPE html>
<html>
<head>
    <title>Kindle Frame: @{target_user}</title>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
        body {{ font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; background: #f8fafc; color: #1e293b; padding: 24px; }}
        .card {{ background: white; padding: 24px; border-radius: 12px; max-width: 900px; margin: 0 auto 20px; box-shadow: 0 2px 4px rgba(0,0,0,0.05); }}
        h1 {{ margin-top: 0; font-size: 24px; }}
        .badge {{ background: #e0f2fe; color: #0369a1; padding: 4px 10px; border-radius: 12px; font-size: 12px; font-weight: 600; }}
    </style>
</head>
<body>
    <div class="card">
        <h1>🖼️ Kindle Instagram Frame Status</h1>
        <p>Target Account: <strong>@{target_user}</strong> <span class="badge">Every 12 hrs</span></p>
        <p>Picture Rotation: <strong>{cycle_interval_min} minutes</strong></p>
        <p>Last Sync: <strong>{last_sync}</strong></p>
    </div>
    <div class="card">
        <h2>Active Photos on Kindle (Current & Previous Post)</h2>
        <div>{images_html}</div>
    </div>
</body>
</html>"""

def main():
    config = load_json("config.json", {})
    target_user = config.get("instagram", {}).get("target_username", "natgeo")
    kindle_width = config.get("kindle", {}).get("width", 1072)
    kindle_height = config.get("kindle", {}).get("height", 1448)
    cycle_interval = config.get("kindle", {}).get("picture_change_interval_seconds", 1800)
    max_posts_to_keep = config.get("kindle", {}).get("max_posts_to_keep", 2)

    os.makedirs(IMAGES_DIR, exist_ok=True)
    os.makedirs("temp", exist_ok=True)
    open(os.path.join(DOCS_DIR, ".nojekyll"), "a").close()

    state = load_json(STATE_FILE, {"active_posts": []})
    active_posts = state.get("active_posts", [])
    known_shortcodes = {p["shortcode"] for p in active_posts}

    logger.info(f"Checking Instagram for @{target_user}...")

    L = instaloader.Instaloader(
        download_pictures=False,
        download_videos=False,
        download_video_thumbnails=False,
        download_geotags=False,
        download_comments=False,
        save_metadata=False
    )

    try:
        profile = instaloader.Profile.from_username(L.context, target_user)
        latest_post = None
        for post in profile.get_posts():
            latest_post = post
            break

        if not latest_post:
            msg = f"No posts found for @{target_user}"
            logger.warning(msg)
            send_alert("Kindle Sync Warning", msg)
            return

        shortcode = latest_post.shortcode

        # If already synced, just refresh metadata
        if shortcode in known_shortcodes:
            logger.info(f"Post {shortcode} already downloaded. No new post.")
        else:
            logger.info(f"New post found: {shortcode} ({latest_post.date_utc})")
            image_urls = []
            if latest_post.typename == "GraphSidecar":
                for node in latest_post.get_sidecar_nodes():
                    if not node.is_video:
                        image_urls.append(node.display_url)
            elif not latest_post.is_video:
                image_urls.append(latest_post.url)

            processed_filenames = []
            for idx, url in enumerate(image_urls):
                temp_raw = os.path.join("temp", f"{shortcode}_{idx}.jpg")
                filename = f"{shortcode}_{idx}.png"
                final_path = os.path.join(IMAGES_DIR, filename)

                logger.info(f"Downloading image {idx+1}/{len(image_urls)} from {shortcode}...")
                urllib.request.urlretrieve(url, temp_raw)

                logger.info(f"Dithering for Kindle e-ink: {filename}...")
                process_image_for_kindle(temp_raw, final_path, kindle_width, kindle_height)

                if os.path.exists(temp_raw):
                    os.remove(temp_raw)
                processed_filenames.append(filename)

            if processed_filenames:
                active_posts.insert(0, {
                    "shortcode": shortcode,
                    "date": latest_post.date_utc.isoformat(),
                    "images": processed_filenames
                })

            # Sliding window: delete posts older than max_posts_to_keep (2 posts prior)
            while len(active_posts) > max_posts_to_keep:
                expired = active_posts.pop()
                logger.info(f"Pruning expired post {expired['shortcode']}...")
                for img_name in expired.get("images", []):
                    img_path = os.path.join(IMAGES_DIR, img_name)
                    if os.path.exists(img_path):
                        try:
                            os.remove(img_path)
                            logger.info(f"Deleted expired image: {img_name}")
                        except Exception as e:
                            logger.error(f"Error deleting {img_path}: {e}")

        # Update state and manifest
        all_active_images = []
        for p in active_posts:
            for img in p.get("images", []):
                if os.path.exists(os.path.join(IMAGES_DIR, img)):
                    all_active_images.append(img)

        now_str = datetime.datetime.now(datetime.timezone.utc).isoformat()
        state["active_posts"] = active_posts
        state["last_sync"] = now_str

        with open(STATE_FILE, "w", encoding="utf-8") as f:
            json.dump(state, f, indent=2)

        manifest = {
            "status": "ok",
            "cycle_interval_seconds": cycle_interval,
            "last_sync": now_str,
            "total_images": len(all_active_images),
            "images": all_active_images
        }
        with open(MANIFEST_FILE, "w", encoding="utf-8") as f:
            json.dump(manifest, f, indent=2)

        html = generate_html_gallery(active_posts, cycle_interval // 60, target_user, now_str)
        with open(INDEX_FILE, "w", encoding="utf-8") as f:
            f.write(html)

        logger.info(f"Sync finished successfully. {len(all_active_images)} active images.")

    except Exception as e:
        err = f"Sync failed for @{target_user}: {str(e)}"
        logger.error(err, exc_info=True)
        send_alert("Kindle Sync Alert", err)
        # Existing photos & manifest remain untouched so Kindle continues cycling

if __name__ == "__main__":
    main()
