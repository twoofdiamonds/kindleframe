# 🖼️ Kindle Instagram Photo Frame (100% Free via GitHub Actions)

This setup runs **24/7 online for free** without needing a laptop, server, or credit card.

- **GitHub Actions** runs automatically every 12 hours via cron.
- It fetches the newest post from your target public Instagram account (including multi-photo carousels).
- It runs e-ink image processing (contrast boost + Floyd-Steinberg dithering) tailored for your Kindle model.
- It maintains the 2-post sliding window (automatically deleting photos from 2 posts prior).
- It publishes everything to your free **GitHub Pages** website.
- If an error occurs, an instant alert is pushed to your phone via **ntfy.sh** (or Discord/Telegram), and existing photos remain active.
- Your Kindle fetches the processed photos over Wi-Fi and cycles them using `rtcwake` deep-sleep.

---

## 🚀 Setup Guide (Takes ~3 minutes)

### Step 1: Create a Repository on GitHub
1. Go to [github.com/new](https://github.com/new) and create a repository (e.g. named `kindle-frame`).
   - You can set it to **Public** (required for free GitHub Pages on standard accounts).

### Step 2: Push These Files to Your Repository
Open PowerShell on your computer and run:
```powershell
cd "c:\Users\daaks\Downloads\My results weird_files\kindle_github_actions"
git init
git add .
git commit -m "Initial Kindle Frame setup"
git branch -M main
git remote add origin https://github.com/YOUR_GITHUB_USERNAME/kindle-frame.git
git push -u origin main
```
*(Replace `YOUR_GITHUB_USERNAME` with your actual GitHub username).*

---

### Step 3: Enable GitHub Permissions & GitHub Pages

#### A. Grant Workflow Write Permissions (Required to commit photos)
1. In your GitHub repository, click **Settings** → **Actions** → **General**.
2. Scroll down to **Workflow permissions**.
3. Select **Read and write permissions** and click **Save**.

#### B. Enable GitHub Pages
1. In your repository, click **Settings** → **Pages**.
2. Under **Build and deployment**:
   - Source: **Deploy from a branch**
   - Branch: **`main`**
   - Folder: **`/docs`** (Select `/docs` instead of `/ (root)`)
3. Click **Save**.
4. Your GitHub Pages URL will be:
   `https://YOUR_GITHUB_USERNAME.github.io/kindle-frame/`

---

### Step 4: Run the First Sync Test

1. Click on the **Actions** tab in your repository.
2. Under Workflows on the left, click **Kindle Instagram Photo Sync**.
3. Click the **Run workflow** dropdown button on the right, and click **Run workflow**.
4. In ~30 seconds, it will turn green ✅.
5. Open your GitHub Pages link in any browser on your phone or laptop (`https://YOUR_GITHUB_USERNAME.github.io/kindle-frame/`) to see your live web gallery of dithered Kindle photos!

---

### Step 5: Configure Your Kindle

1. Connect your jailbroken Kindle to your computer or SSH into it.
2. Copy `kindle_client/kindle_sync.sh` to `/mnt/us/kindle_sync.sh`.
3. Open `kindle_sync.sh` and set line 8 to your GitHub Pages URL:
   ```sh
   BASE_URL="https://YOUR_GITHUB_USERNAME.github.io/kindle-frame"
   ```
4. Start the script on your Kindle:
   ```sh
   chmod +x /mnt/us/kindle_sync.sh
   /mnt/us/kindle_sync.sh > /mnt/us/kindle.log 2>&1 &
   ```

---

## ⚙️ Customization (`config.json`)

To change the Instagram username or rotation speed, edit [`config.json`](config.json) in your repository and commit it:

```json
{
  "instagram": {
    "target_username": "natgeo"
  },
  "kindle": {
    "width": 1072,
    "height": 1448,
    "picture_change_interval_seconds": 1800,
    "max_posts_to_keep": 2
  },
  "notifications": {
    "ntfy": {
      "enabled": true,
      "topic": "my-kindle-alerts-12345"
    }
  }
}
```

- **Rotation speed**: Change `picture_change_interval_seconds` (e.g., `900` for 15 mins, `1800` for 30 mins). The Kindle automatically updates its timer on the next 12-hour sync!
- **Instant Phone Alerts**: Download the free **ntfy** app on iOS/Android, subscribe to the topic name in `config.json`, and you'll get instant alerts if Instagram ever rate-limits or fails.
