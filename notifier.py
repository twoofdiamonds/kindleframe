import os
import json
import logging
import requests

logger = logging.getLogger("kindle_notifier")

def send_alert(title: str, message: str, config_path="config.json"):
    """
    Sends an alert across ntfy.sh, Discord, or Telegram.
    Can read from config.json or environment variables (e.g., GitHub Secrets).
    """
    config = {}
    if os.path.exists(config_path):
        try:
            with open(config_path, "r", encoding="utf-8") as f:
                config = json.load(f)
        except Exception as e:
            logger.error(f"Error reading config: {e}")

    notifications = config.get("notifications", {})

    # 1. ntfy.sh
    ntfy_cfg = notifications.get("ntfy", {})
    topic = os.environ.get("NTFY_TOPIC") or ntfy_cfg.get("topic")
    if (ntfy_cfg.get("enabled") or os.environ.get("NTFY_TOPIC")) and topic:
        try:
            requests.post(
                f"https://ntfy.sh/{topic}",
                data=message.encode("utf-8"),
                headers={"Title": title, "Priority": "high", "Tags": "warning,kindle"},
                timeout=10
            )
            logger.info("Sent alert to ntfy.sh")
        except Exception as e:
            logger.error(f"ntfy error: {e}")

    # 2. Discord Webhook
    discord_url = os.environ.get("DISCORD_WEBHOOK_URL") or notifications.get("discord", {}).get("webhook_url")
    if discord_url:
        try:
            requests.post(
                discord_url,
                json={"embeds": [{"title": f"⚠️ {title}", "description": message, "color": 15158332}]},
                timeout=10
            )
            logger.info("Sent alert to Discord")
        except Exception as e:
            logger.error(f"Discord error: {e}")

    # 3. Telegram
    tg_token = os.environ.get("TELEGRAM_BOT_TOKEN") or notifications.get("telegram", {}).get("bot_token")
    tg_chat = os.environ.get("TELEGRAM_CHAT_ID") or notifications.get("telegram", {}).get("chat_id")
    if tg_token and tg_chat:
        try:
            requests.post(
                f"https://api.telegram.org/bot{tg_token}/sendMessage",
                json={"chat_id": tg_chat, "text": f"⚠️ *{title}*\n\n{message}", "parse_mode": "Markdown"},
                timeout=10
            )
            logger.info("Sent alert to Telegram")
        except Exception as e:
            logger.error(f"Telegram error: {e}")
