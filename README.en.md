[![🇬🇧 English](https://img.shields.io/badge/README-English-blue)](README.en.md)
[![🇹🇷 Türkçe](https://img.shields.io/badge/README-Türkçe-red)](README.md)
# Keenetic Zapret2 Manager (KZM2)

## 📦 Installation & Download

[![Stars](https://img.shields.io/github/stars/RevolutionTR/keenetic-zapret2-manager?style=for-the-badge)](https://github.com/RevolutionTR/keenetic-zapret2-manager/stargazers)
[![Latest Release](https://img.shields.io/github/v/release/RevolutionTR/keenetic-zapret2-manager?style=for-the-badge)](https://github.com/RevolutionTR/keenetic-zapret2-manager/releases/latest)
<br>
<br>
[![Full Setup Guide](https://img.shields.io/badge/Full%20Setup-Guide-success?style=for-the-badge)](https://github.com/RevolutionTR/keenetic-zapret2-manager/blob/main/docs/installation_guide_en.md)
[![User Guide](https://img.shields.io/badge/Usage-Menu_Guide-blue?style=for-the-badge)](https://github.com/RevolutionTR/keenetic-zapret2-manager/blob/main/docs/user_guide_en.md)
[![Telegram](https://img.shields.io/badge/Telegram-Setup-2CA5E0?style=for-the-badge)](https://github.com/RevolutionTR/keenetic-zapret2-manager/blob/main/docs/telegram_en.md)
<br>
[![Platform](https://img.shields.io/badge/Platform-Keenetic-1f6feb?style=for-the-badge)](https://keenetic.com.tr) [![Platform](https://img.shields.io/badge/Platform-Entware-orange?style=for-the-badge)](https://entware.net)
<br>
![Languages](https://img.shields.io/badge/Languages-TR%20%7C%20EN-orange?style=for-the-badge)
[![Open Source](https://img.shields.io/badge/Open%20Source-Yes-brightgreen?style=for-the-badge)](https://github.com/RevolutionTR/keenetic-zapret2-manager)
[![Mobile Compatible](https://img.shields.io/badge/Mobile%20Compatible-100%25-brightgreen?style=for-the-badge&logo=android)](https://github.com/RevolutionTR/keenetic-zapret2-manager)

> [!WARNING]
> **Important notice for existing KZM users:**
> **Before** installing KZM2, you must fully remove your existing KZM installation using
> **Menu U → KZM + Zapret Full Uninstall**.
> KZM and KZM2 must not be installed at the same time — iptables rules and service files will conflict.
<br>
<br>

<img src="docs/images/KZM2_Main_Menu.png" width="800">

<img src="docs/images/zapret2_menu2.png" width="800">

<img src="docs/images/zapret2_menu4.png" width="800">

<img src="docs/images/zapret2_menu5.png" width="800">

## 🚀 KZM2 WEB UI

<img src="docs/images/KZM2_Main1.png" width="800">

<img src="docs/images/KZM2_Main2.png" width="800">

<img src="docs/images/KZM2_Main3.png" width="800">

<img src="docs/images/KZM2_Main4.png" width="800">

<img src="docs/images/KZM2_Main5.png" width="800">

<img src="docs/images/KZM2_Main6.png" width="800">

> [!WARNING]
> ## 🔒 Web Panel Security Notice
>
> The KZM2 Web Panel is intended to be used **only on trusted local networks (Trusted LAN)**.
>
> **Not recommended:**
> - Exposing the panel to WAN/Internet
> - Port forwarding
> - Access from Guest networks
> - Access from untrusted IoT/VLAN segments
>
> The Web Panel performs **administrator-level operations**, including Zapret2 restart, DPI profile changes, hostlist/IPSET management and system actions.
>
> For this reason, it should only be used within a **trusted home/office management network**.
> 

## ✅ Tested Keenetic OS Versions

This script has been tested on the following Keenetic OS versions:

- **Keenetic OS 5.0.12**
- **Keenetic OS 4.3.6.4**

> Not tested on older Keenetic OS versions.  
> On older versions, OPKG/Entware packages, iptables/ipset behaviour or binary compatibility may differ.

## ✅ Recommended Setup:
KZM2 needs a working Entware/OPKG environment mounted under `/opt`. This `/opt`
mount can be backed by internal storage or by a USB drive.

- On newer Keenetic models with around 100 MB of internal storage, internal storage is usually enough for KZM2/Zapret2 only.
- On older low-storage models, or when using extra Entware packages, heavy logs, Web Panel/monitoring, USB/external storage is recommended.
- The KZM2 script runs from `/opt/lib/opkg`, while Zapret2 files are managed under `/opt/zapret2`.

---

## 📖 About the Project

**Zapret2 management and automation script for Keenetic routers/modems**

This project provides **easy installation** of Zapret2 on Keenetic devices, **DPI profile management**,  
**client selection via IPSET**, **menu-driven usage** and  
**version tracking via GitHub**.

### Important Note on DNS

Zapret2 is designed to bypass DPI (Deep Packet Inspection) based restrictions.  
**It does not resolve DNS-based blocking or ISP DNS manipulation.**

For this reason, when using Zapret2 on some ISPs:
- DoH (DNS over HTTPS),
- DoT (DNS over TLS),
- or a trusted third-party DNS

is **strongly recommended**.

ISP DNS servers may return incorrect IPs for blocked domains.  
In that case, even if Zapret2 is working, the connection may still fail.

---

## 🚀 Features

### Zapret2 Installation & Management
- Automatic Zapret2 installation and removal
- Full install / clean uninstall from a single menu
- Safe management of Zapret2 files on the system

### DPI Profile Management
- Default Zapret2 profile: **Turk Telekom Fiber (TTL2 fake)**
- Custom DPI editing split into **HTTP / TLS / QUIC** sections in the Web Panel
- Automatic DPI parameter application based on Blockcheck results
- **dry-run / syntax validation** to reject invalid manual parameters
- **Automatic Zapret2 restart** after profile change

### IPSET-Based Traffic Control
- Apply Zapret2 to the entire network (**Global mode**)
- Apply Zapret2 to selected IPs only (**Smart mode**)
- Client-based control via IPSET list

### Hostlist / Autohostlist System
- Automatic learning of DPI-detected domains (Autohostlist)
- Manual domain add / remove (User hostlist)
- Excluded domain list (Exclude)

### IPv6 Support
- IPv6 Zapret2 support (optional)
- Enable / disable IPv6 from the menu
- Colour-coded IPv6 status display on the status screen

### Backup and Restore
- Back up individual `.txt` files under IPSET
- Restore selected files
- **Automatic Zapret2 restart** after restore

### Version & Update Checks
- Installed Zapret2 version information
- Manager (script) version check (GitHub)
- Latest version notifications

### CLI Shortcuts
- `kzm`
- `KZM`
- `kzm2`
- `KZM2`
- `keenetic-zapret2`
- Run the script without typing the full path

### Multi-Language Interface
- Turkish / English (TR / EN) language support
- Dictionary-based translation system

### User-Friendly Interface
- Colourful and readable menu layout
- Clear status indicators
- Protections against misconfiguration

---

## 🔍 Blockcheck → Automatic DPI Smart Flow

The most stable DPI parameter is automatically detected from the Blockcheck summary (SUMMARY) result.

A decision screen is presented to the user:

- **[1] Apply** → Parameter is activated as the DPI profile
- **[2] Inspect Parameter**
- **[3] Save Only**
- **[0] Cancel**

Automatic DPI only works from the summary test (the full test does not apply directly).

The active DPI state is clearly shown in the menu:
- Default / Manual
- Blockcheck (Automatic)

Applied parameters are also listed separately.

---

## 📊 DPI Health Score

A DPI Health Score is calculated after Blockcheck (e.g. 8.5 / 10).

Sub-checks are shown to the user in a readable format:

- ✔ DNS consistency
- ✔ TLS 1.2 status
- ⚠ UDP 443 weak / at risk

Symbols and text are formatted for terminal compatibility and readability.

---

## 🤖 Telegram Notifications

To receive instant notifications from your router:  
➡️ [Telegram Setup Guide](docs/telegram_en.md)

---

## 🧹 Clearing Test Results

A new option has been added to the **Blockcheck Test** menu:

**"Clear Test Results"**

The following files are safely deleted:
- `blockcheck_*.txt`
- `blockcheck_summary_*.txt`

This prevents the `/opt/zapret2` directory from growing over time.

---

## 💾 Script Backup Management

A backup is taken automatically during script updates.

Backups are now saved with a `.sh` extension and can be restored:

```
keenetic_zapret2_manager.sh.bak_26.1.30_YYYYMMDD_HHMMSS.sh
```

A new option has been added to the **Local Storage (Backups)** menu:

**"Clear Backups"**

Only backups belonging to this script are removed:
- `keenetic_zapret2_manager.sh.bak_*`

---

## ⚠️ Prerequisites (REQUIRED)

### 1️⃣ Entware must be installed


### 2️⃣ OPKG must be installed

---

## 🧩 What Happens on First Install?

- OPKG packages are checked
- Zapret2 is downloaded and adapted for Keenetic
- Exit interface is requested (e.g. `ppp0`)
- Default DPI profile is applied:  
  **Turk Telekom Fiber (TTL2 fake)**
- Zapret2 is started automatically

> The DPI profile can be changed later from the menu.

---

## 🎛️ DPI Profile Management

Manages the DPI bypass method. After changes are applied, Zapret2 **restarts automatically.**

KZM2 uses **Turk Telekom Fiber (TTL2 fake)** as the default profile and applies it automatically during the first installation.

### Usage Modes

| Mode | Description |
|------|-------------|
| **Default Profile** | The recommended and default DPI profile used by KZM2 (TTL2 fake) |
| **Custom (Manual) DPI Profile** | Advanced users can manually edit `NFQWS2_OPT` parameters |
| **Blockcheck (Auto)** | Automatically applies the most suitable DPI parameter based on Blockcheck results |

### Default Profile

KZM2 applies the following profile during installation:

- **Turk Telekom Fiber (TTL2 fake)** → recommended baseline profile

For many users, no further configuration is required.

### Custom (Manual) DPI Profile

The Web Panel allows separate editing of:

- **HTTP**
- **TLS / HTTPS**
- **QUIC / HTTP3**

Advanced users can modify parameters such as:

- `repeats`
- `ip_ttl`
- `autottl`
- `badsum`
- `multisplit`
- different `lua-desync` strategies

Before applying, the configuration is automatically validated (syntax check / dry-run). Invalid or broken parameters are rejected.

⚠️ **This section is intended for advanced users only. Incorrect changes may break internet access.**

### Blockcheck (Auto)

The Blockcheck menu (B) can automatically detect the most suitable DPI parameter.

The detected parameter can be:

- applied as the active profile
- saved only
- reviewed before applying

When active, the status is shown as:

- **Blockcheck (Auto)**

👉 If you are unsure which configuration to use, start with the **Default Profile**. If issues occur, run **Blockcheck (B)**.

---

## 🌐 IPSET (Client Selection)

The active mode is shown automatically above the IPSET menu:

- 🟢 **Mode: Entire network**  
  → Zapret2 active for all LAN clients

- 🟡 **Mode: Selected IPs**  
  → Zapret2 active only for the specified **static IPs**

Local networks (RFC1918, loopback, CGNAT etc.) are always technically bypassed (`nozapret2`).

---

## 🔄 Version Check

- Zapret2 version is queried from GitHub
- Manager (script) version is compared against the GitHub Release tag

### Version Format

```
YY.MM.DD(.N)
```

Examples:
- `v26.1.24`
- `v26.1.24.2` → second release published on the same day

---

## 📜 License

This project is released under the **GNU GPLv3** license.

- You may freely use it
- Modify it
- Distribute it  

However, it must be shared under the **same license**.

---

## ⚠️ Disclaimer

This script affects:
- Network traffic
- DPI / iptables / ipset configurations

Incorrect configuration may cause connectivity issues.  
Use is entirely **at the user's own risk**.

---

## 🤝 Contributions & Feedback

- You can open an issue
- You can submit a feature request
- Pull Requests are welcome

📌 **GitHub Repo:**  
https://github.com/RevolutionTR/keenetic-zapret2-manager

---
## 🔔 About Derivative Projects

Projects inspired by this project's UI design, menu architecture, or overall structure
are expected to provide proper attribution:

**Source:** [Keenetic Zapret2 Manager (KZM2)](https://github.com/RevolutionTR/keenetic-zapret2-manager) by RevolutionTR

Usage is free under the GPL-3.0 license, however providing attribution in derivative
works is an ethical requirement.
<br>
## Legal Notice
Keenetic and the Keenetic logo are registered trademarks of Keenetic Ltd.
This project has no official affiliation, partnership, or sponsorship with Keenetic Ltd.
The Keenetic logo is used solely to indicate that this tool is designed for Keenetic devices.
