"""
Kindle Instagram Sync — Playwright-based scraper.

Uses a real headless Chromium browser to load Instagram's profile page,
so Instagram sees a legitimate browser session — not an API bot.
Falls back to RapidAPI proxy if RAPIDAPI_KEY is set.
"""

import os
import json
import logging
import datetime
import urllib.request
import re
import time
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


# ─── Strategy 1: Playwright (Real Headless Chromium) ────────────────────────

def fetch_via_playwright(target_user: str, session_id: str):
    """
    Opens Instagram in a real headless Chromium browser with the user's
    session cookie. Instagram sees a legitimate browser — not an API call.
    Extracts the latest post's shortcode and image URLs from the rendered DOM.
    """
    from playwright.sync_api import sync_playwright

    logger.info(f"Launching headless Chromium for @{target_user}...")

    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        context = browser.new_context(
            viewport={"width": 1280, "height": 900},
            user_agent=(
                "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                "AppleWebKit/537.36 (KHTML, like Gecko) "
                "Chrome/120.0.0.0 Safari/537.36"
            ),
            locale="en-US",
        )

        # Inject session cookie so Instagram thinks we're logged in
        if session_id:
            clean_sid = session_id.strip('"\'  \t\r\n')
            context.add_cookies([
                {
                    "name": "sessionid",
                    "value": clean_sid,
                    "domain": ".instagram.com",
                    "path": "/",
                    "httpOnly": True,
                    "secure": True,
                    "sameSite": "None",
                },
            ])
            logger.info("Injected sessionid cookie into browser context.")

        page = context.new_page()

        # Block heavy resources to speed up page load
        page.route("**/*.{mp4,webm,ogg,woff2,woff}", lambda route: route.abort())

        profile_url = f"https://www.instagram.com/{target_user}/"
        logger.info(f"Navigating to {profile_url} ...")
        page.goto(profile_url, wait_until="domcontentloaded", timeout=45000)

        # Wait for the post grid to render
        try:
            page.wait_for_selector("article a[href*='/p/']", timeout=20000)
        except Exception:
            # Might be a login wall or the profile loaded differently
            logger.warning("Could not find post links on page, trying alternative selectors...")
            try:
                page.wait_for_selector("a[href*='/p/']", timeout=10000)
            except Exception:
                # Last resort: take a screenshot for debugging and bail
                debug_path = "temp/debug_screenshot.png"
                os.makedirs("temp", exist_ok=True)
                page.screenshot(path=debug_path)
                logger.error(f"No posts found on page. Debug screenshot saved to {debug_path}")
                logger.error(f"Page title: {page.title()}")
                browser.close()
                return None

        # Find all post links — format: /p/SHORTCODE/
        post_links = page.query_selector_all("a[href*='/p/']")
        if not post_links:
            logger.error("No post links found in DOM.")
            browser.close()
            return None

        # Extract shortcodes from the first (latest) post link
        first_href = post_links[0].get_attribute("href")
        match = re.search(r"/p/([A-Za-z0-9_-]+)/", first_href)
        if not match:
            logger.error(f"Could not extract shortcode from href: {first_href}")
            browser.close()
            return None

        shortcode = match.group(1)
        logger.info(f"Found latest post: {shortcode}")

        # Navigate into the post to get full-resolution image(s)
        post_url = f"https://www.instagram.com/p/{shortcode}/"
        logger.info(f"Opening post: {post_url}")
        page.goto(post_url, wait_until="domcontentloaded", timeout=30000)
        time.sleep(3)  # Let lazy images load

        # Dismiss cookie / banner overlays if present
        _dismiss_overlays(page)

        # Collect image URLs from the post
        image_urls = _extract_post_images(page, shortcode)

        # Check for carousel — click through "Next" buttons
        carousel_attempts = 0
        max_carousel = 10
        while carousel_attempts < max_carousel:
            next_btn = page.query_selector("button[aria-label='Next']")
            if not next_btn:
                break
            try:
                # Use evaluate click to bypass overlay interceptors
                page.evaluate("btn => btn.click()", next_btn)
            except Exception:
                try:
                    next_btn.click(timeout=2000, force=True)
                except Exception:
                    logger.info("Could not click next button, stopping carousel pagination.")
                    break

            time.sleep(1.5)
            new_images = _extract_post_images(page, shortcode)
            before_count = len(image_urls)
            for url in new_images:
                if url not in image_urls:
                    image_urls.append(url)
            if len(image_urls) == before_count:
                break  # No new images found, carousel exhausted
            carousel_attempts += 1

        browser.close()

        if not image_urls:
            logger.error("Could not extract any image URLs from the post.")
            return None

        logger.info(f"Extracted {len(image_urls)} image(s) from post {shortcode}")
        return {
            "shortcode": shortcode,
            "date_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            "image_urls": image_urls,
        }


def _dismiss_overlays(page):
    """Dismisses cookie consent banners or login dialogs if present."""
    # List of common button labels on Instagram for cookies / dialogs
    selectors = [
        "button:has-text('Allow all cookies')",
        "button:has-text('Decline optional cookies')",
        "button:has-text('Only allow essential cookies')",
        "button:has-text('Allow')",
        "button:has-text('Accept')",
        "button[aria-label='Close']",
        "div[role='dialog'] button",
    ]
    for sel in selectors:
        try:
            btn = page.query_selector(sel)
            if btn:
                page.evaluate("el => el.click()", btn)
                time.sleep(0.5)
                break
        except Exception:
            pass


def _extract_post_images(page, shortcode: str) -> list:
    """Extract image URLs from a post page's DOM."""
    urls = []
    # Primary: article img tags with src containing instagram's CDN
    img_elements = page.query_selector_all("article img[src*='instagram']")
    if not img_elements:
        # Fallback: any img with instagram CDN URL
        img_elements = page.query_selector_all("img[src*='cdninstagram'], img[src*='scontent']")

    for el in img_elements:
        src = el.get_attribute("src") or ""
        # Skip tiny profile pictures & icons
        if src and ("150x150" not in src) and ("44x44" not in src) and ("s150x150" not in src):
            if src not in urls:
                urls.append(src)

    # Also check srcset for higher-res versions
    for el in img_elements:
        srcset = el.get_attribute("srcset") or ""
        if srcset:
            # Pick the highest resolution from srcset
            parts = srcset.split(",")
            if parts:
                last = parts[-1].strip().split(" ")[0]
                if last and last not in urls and "150x150" not in last:
                    urls.append(last)

    return urls


# ─── Strategy 2: RapidAPI Proxy (Residential IPs) ──────────────────────────

def fetch_via_rapidapi(target_user: str, api_key: str):
    """
    Fetches the latest post using RapidAPI's Instagram Scraper.
    Bypasses datacenter blocks using rotating residential proxies.
    """
    import requests
    url = "https://instagram-scraper-api2.p.rapidapi.com/v1/posts"
    params = {"username_or_id_or_url": target_user}
    headers = {
        "x-rapidapi-key": api_key,
        "x-rapidapi-host": "instagram-scraper-api2.p.rapidapi.com"
    }
    logger.info(f"Fetching posts for @{target_user} via RapidAPI proxy...")
    resp = requests.get(url, headers=headers, params=params, timeout=20)
    resp.raise_for_status()
    data = resp.json()
    items = data.get("data", {}).get("items", [])
    if not items:
        return None
    post = items[0]
    shortcode = post.get("code")
    date_str = datetime.datetime.fromtimestamp(post.get("taken_at", 0), datetime.timezone.utc).isoformat()
    image_urls = []

    if "carousel_media" in post:
        for m in post["carousel_media"]:
            candidates = m.get("image_versions2", {}).get("candidates", [])
            if candidates:
                image_urls.append(candidates[0]["url"])
    elif "image_versions2" in post:
        candidates = post.get("image_versions2", {}).get("candidates", [])
        if candidates:
            image_urls.append(candidates[0]["url"])

    return {
        "shortcode": shortcode,
        "date_utc": date_str,
        "image_urls": image_urls
    }


# ─── Main ───────────────────────────────────────────────────────────────────

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
    
    # If the target username changed, purge all previous account's photos
    previous_user = state.get("target_username")
    if previous_user and previous_user.lower() != target_user.lower():
        logger.info(f"Target account changed from @{previous_user} to @{target_user}. Purging previous photos...")
        for p in state.get("active_posts", []):
            for img_name in p.get("images", []):
                old_path = os.path.join(IMAGES_DIR, img_name)
                if os.path.exists(old_path):
                    try:
                        os.remove(old_path)
                    except Exception:
                        pass
        state["active_posts"] = []

    state["target_username"] = target_user
    active_posts = state.get("active_posts", [])
    known_shortcodes = {p["shortcode"] for p in active_posts}

    logger.info(f"Checking Instagram for @{target_user}...")

    # Decide which fetch strategy to use
    rapidapi_key = os.environ.get("RAPIDAPI_KEY")
    session_id = os.environ.get("INSTAGRAM_SESSIONID", "")

    try:
        post_data = None

        if rapidapi_key:
            # Strategy 2: RapidAPI proxy (if key is set)
            post_data = fetch_via_rapidapi(target_user, rapidapi_key)
            if not post_data:
                msg = f"No posts found for @{target_user} via RapidAPI"
                logger.warning(msg)
                send_alert("Kindle Sync Warning", msg)
                return

        else:
            # Strategy 1: Playwright headless browser (default)
            post_data = fetch_via_playwright(target_user, session_id)
            if not post_data:
                msg = f"Could not fetch posts for @{target_user} via Playwright browser. Check debug screenshot in temp/."
                logger.error(msg)
                send_alert("Kindle Sync Error", msg)
                return

        shortcode = post_data["shortcode"]
        date_utc = post_data["date_utc"]
        image_urls = post_data["image_urls"]

        # If already synced, just refresh metadata
        if shortcode in known_shortcodes:
            logger.info(f"Post {shortcode} already downloaded. No new post.")
        else:
            logger.info(f"New post found: {shortcode} ({date_utc})")

            processed_filenames = []
            for idx, url in enumerate(image_urls):
                temp_raw = os.path.join("temp", f"{shortcode}_{idx}.jpg")
                filename = f"{shortcode}_{idx}.png"
                final_path = os.path.join(IMAGES_DIR, filename)

                logger.info(f"Downloading image {idx+1}/{len(image_urls)} from {shortcode}...")
                # Instagram CDN URLs may require a browser-like User-Agent
                req = urllib.request.Request(url, headers={
                    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
                    "Referer": "https://www.instagram.com/",
                })
                with urllib.request.urlopen(req, timeout=30) as resp:
                    with open(temp_raw, "wb") as f:
                        f.write(resp.read())

                logger.info(f"Dithering for Kindle e-ink: {filename}...")
                process_image_for_kindle(temp_raw, final_path, kindle_width, kindle_height)

                if os.path.exists(temp_raw):
                    os.remove(temp_raw)
                processed_filenames.append(filename)

            if processed_filenames:
                active_posts.insert(0, {
                    "shortcode": shortcode,
                    "date": date_utc,
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
