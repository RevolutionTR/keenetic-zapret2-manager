# 🤖 Telegram Notifications and Bot – Setup Guide

This guide explains how to set up **Telegram notifications and two-way bot control** for Keenetic Zapret2 Manager in just a few steps.

With the Telegram integration, you can receive **real-time system and Zapret2 status messages** from your router and **manage your router directly via Telegram**.

---

## 📌 What is the Telegram Integration?

KZM2's Telegram integration consists of two parts:

### 1. Notifications (One-Way)
Automatic notifications sent from the router to Telegram:
- 🚨 Zapret2 may have stopped (if auto-restart fails)
- ✅ Zapret2 is running again
- ⚠️ CPU / RAM / Disk usage is high
- 📌 Timestamped status messages with headers

### 2. Bot Control (Two-Way)
Send commands from Telegram to your router:
- 📊 Query live system status
- 🔧 Start / stop / restart Zapret2
- 📡 View connected devices
- 📶 Turn WiFi on / off
- 🔁 Reboot the router
- 📋 View logs

> Telegram integration is **optional**. The system works normally without it.

---

## 1️⃣ Creating a Telegram Bot

1. Open a conversation with **@BotFather** on Telegram
2. Send the following commands in order:

   `/start`

   `/newbot`

3. BotFather will give you a **BOT TOKEN**
   (example: `123456:ABC-DEF...`)
4. Save this token and **NEVER share it with anyone!**

---

## 2️⃣ Finding Your Chat ID

1. Send **at least one message** to the bot you just created — otherwise the chat ID will not appear
2. Open the following URL in your browser:

   `https://api.telegram.org/bot<BOT_TOKEN>/getUpdates`

   > Note: Replace `<BOT_TOKEN>` — remove the `<>` brackets and write it as `bot12345:KEKDK.../`

3. Find the following field in the output:

   `"chat": {"id": 123456789`

   That number is your Chat ID.

---

## 3️⃣ Saving via the Script

Launch Keenetic Zapret2 Manager and go to the **Telegram Notification Settings** menu (Menu 15).

From there:
1. Select **Save/Update Token & Chat ID** and enter your Bot Token and Chat ID
2. Use the **Send Test Message** option

If the test message arrives in Telegram, the notification setup is complete ✅

---

## 4️⃣ Enabling the Telegram Bot (Two-Way Control)

To activate bot control:

1. Go to Menu 15 → **4) Telegram Bot Management**
2. Select **1) Enable / Configure Bot**
3. Enter the polling interval (default: 5 seconds)
4. If the bot starts successfully, you will see the message `Bot ACTIVE - 2-way communication running`

Once the bot is enabled, it will **start automatically** even after a router reboot (via `/opt/etc/init.d/S98kzm2_telegram`).

---

## 📱 Bot Commands

When the bot is active, type `/` in Telegram to access the command list:

| Command | Description |
|---------|-------------|
| `/start`, `/menu` | Opens the main menu |
| `/durum`, `/status` | Shows live system status |
| `/zapret2` | Goes to the Zapret2 management menu |
| `/sistem`, `/system` | Goes to the system and router menu |
| `/kzm2` | Goes to the KZM2 management menu |
| `/help`, `/yardim` | Shows a detailed help message |

> **Note:** Commands are only accepted from the configured Chat ID.

---

## 🔒 Security

- Notifications and commands are **only sent to / accepted from the configured Chat ID**
- The bot verifies the Chat ID to block unauthorized access
- **Never share your Bot Token** — anyone with the token can control the bot

---

## ❓ Frequently Asked Questions

**Is Telegram required?**
No. If you skip the setup, the system works normally.

**Do I need to reconfigure after a reboot?**
No. The Bot Token, Chat ID, and bot autostart settings are persistent. The bot starts automatically when the router reboots.

**Can I manage my router by sending commands from Telegram?**
Yes. As of v26.3.3, Telegram works **two-way**. With the bot enabled, you can manage your router using commands like `/status`, `/zapret2`, `/system` and inline buttons.

**What happens if the bot crashes?**
If HealthMon is active and `HM_TGBOT_WATCHDOG=1` is set, the bot is checked on every monitoring cycle and automatically restarted if it has crashed.

**The command list (`/`) is not showing in Telegram.**
When the bot first starts, it automatically registers the command list with Telegram. If it is not visible, fully close and reopen the app (this clears the Telegram cache).

**Will logs fill up the disk?**
No. Logs are kept under `/tmp` and are automatically trimmed when the size limit is reached.

---

## 🧪 Troubleshooting

**Test message is not arriving**
- Is the Bot Token correct?
- Is the Chat ID correct?
- Have you sent at least one message to the bot?

**Notifications are not arriving but the test works**
- Is Health Monitor enabled? (Menu 16)
- Has Zapret2 actually stopped?

**Bot is not responding to commands**
- Is the bot enabled? (Menu 15 → Bot Management)
- Check whether the bot is running via the `/tmp/kzm2_telegram_bot.pid` file
- Check the log with `tail -20 /tmp/kzm2_telegram_bot.log`

**Main banner shows `Telegram Bot : INACTIVE`**
- If `TG_BOT_ENABLE=1` is set but the bot is not running: Menu 15 → Bot Management → Restart Bot
