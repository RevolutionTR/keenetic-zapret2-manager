# CUSTOMIZED ZAPRET2 SCRIPT FOR KEENETIC ROUTERS


> [!WARNING]
> **Important notice for existing KZM users:**
> **Before** installing KZM2, you must fully remove your existing KZM installation using
> **Menu U → KZM + Zapret Full Uninstall**.
> KZM and KZM2 must not be installed at the same time — iptables rules and service files will conflict.


## What is Zapret2 and what does it do?
Zapret2 literally means "Prohibition" in Russian. It is a piece of software developed by a Russian programmer for Linux-based systems and is distributed as open-source on GitHub. Zapret2 is a tool used to bypass website access restrictions imposed by ISPs through DPI (Deep Packet Inspection).
  
## Is Zapret2 the only way to bypass access restrictions?
DPI is the most sophisticated and up-to-date access-blocking method used by ISPs. On some ISPs, access restrictions can be bypassed simply by changing the DNS server. For that reason, if you are unsure which blocking method your ISP uses, try changing your DNS before installing Zapret2.

Example DNS addresses (for manual entry via the Keenetic interface):

**1- Google DNS**

DNS server type: `DNS-over-HTTPS`
DNS server URL: `https://dns.google/dns-query`

DNS server type: `DNS-over-TLS`
DNS server URL: `8.8.8.8` (or `8.8.4.4`)
Domain: `dns.google`

**2- Cloudflare DNS**

DNS server type: `DNS-over-HTTPS`
DNS server URL: `https://cloudflare-dns.com/dns-query`

DNS server type: `DNS-over-TLS`
DNS server URL: `1.1.1.1` (or `1.0.0.1`)
Domain: `one.one.one.one`

**3- AdGuard Unfiltered DNS**

DNS server type: `DNS-over-HTTPS`
DNS server URL: `https://unfiltered.adguard-dns.com/dns-query`

DNS server type: `DNS-over-TLS`
DNS server URL: `94.140.14.140` (or `94.140.14.141`)
Domain: `unfiltered.adguard-dns.com`

You can also add these DNS addresses as DoT or DoH directly to your Keenetic device via KZM2 Menu 14 → 3.
  
## Why is a custom script needed, and is it trustworthy?
Installing Zapret2 manually is quite complex for regular users. Scripts make installation and management straightforward. The Keenetic Zapret2 Manager script shared on this page was developed by @Revolution_TR, also a member of the DH (DonanımHaber) forum. With this script, installing and managing Zapret2 is simple; it includes ready-made profiles for common ISPs (primarily Turk Telekom), per-device filtering, backup, update, and many other practical features — and it is still actively developed. The script is distributed as open-source on GitHub, so it is safe to use.
  
## Can this script (Zapret2) be installed on all Keenetic routers? Are there prerequisites?
You can use it on Keenetic models that have a USB port and/or internal storage, support the OPKG package manager, and run KeeneticOS v3.x or later. OPKG is a free package manager for embedded systems such as routers.
  
  
# PRE-INSTALLATION PREPARATION:
  
## === Required Component Options ===
In your router's web interface, go to **MANAGEMENT / System Settings / Component Options** and enable IPv6, DoT (DNS-over-TLS), DoH (DNS-over-HTTPS), SSH Server, and the OPKG components shown below. Then update KeeneticOS — the device will reboot. (**Warning:** If your OS is not already up to date, changing component settings will upgrade KeeneticOS to the latest version.)


<img src="/docs/images/KZM1.png" width="800">



## === DNS Settings ===

In your router's web interface, go to **NETWORK RULES / Internet Security / DNS Configuration**. Use the "+ Add Server" button to add DoT and DoH DNS servers. Sample DoH DNS providers: Google, Cloudflare, Adguard, Quad9. Before enabling "Ignore ISP-provided DNS" in the next step, make sure DoT, DoH, and the ISP's DNS are all already configured.

You can also add these DNS addresses as DoT or DoH directly to your Keenetic device via KZM2 Menu 14 → 3.

<img src="/docs/images/KZM2.png" width="800">

You can verify your DNS settings at the following addresses:  
[DNS Leak Test](https://www.dnsleaktest.com), [Browser Leaks - DNS](https://browserleaks.com/dns)
  
## === Ignore ISP-provided DNS ===
In your router's web interface, navigate to your internet connection — **INTERNET / Ethernet Cable** (or DSL, depending on your setup). Under ISP Authentication (PPPoE / PPTP / L2TP) / Show Advanced PPPoE Settings, enable **Ignore ISP DNSv4** — and if you use IPv6, also enable **Ignore ISP DNSv6** — then save.

<img src="/docs/images/KZM3.png" width="800">

*(If your router is already set up to install OPKG packages, or you have already installed OPKG packages, you can skip the remaining pre-installation steps.)*
  
Since the following pre-installation steps would make this guide too long and are only indirectly related to Zapret2 installation, I will refer you to your device's online User Manual for details. You can reach the User Manual on the Keenetic Support website by entering your product name or model number: Keenetic Support.
  
The pre-installation steps are described in detail under **User Manual / Management / OPKG** in the online manual. I will occasionally link to the Titan (KN-1812) manual as an example — follow the same steps for your own device: [Titan (KN-1812) – Online User Manual / Management / OPKG](https://destek.keenetic.com.tr/titan/kn-1812/tr/18481-opkg.html)
  
OPKG packages can be installed on internal memory or an external USB drive. To install on a USB drive, the drive must be formatted with the EXT4 file system. For drives to work with EXT4, the "Ext File System" component must be installed on your Keenetic router. You can check and install it under **General System Settings → KeeneticOS Update and Component Options → Component Options**.
  
The internal memory on current devices is around 100 MB, which is sufficient for Zapret2 plus a few other packages. On older Keenetic models this may be lower. For older models with less than 50 MB of internal storage, it is recommended to use an external drive via USB even if only Zapret2 will be installed.
  
The storage you plan to use must first be prepared by installing the OPKG Entware package manager. I will again refer you to the online manual for the required steps for each storage option.
  
## === If using internal memory ===
User Manual / Management / OPKG / Installing OPKG Entware in the Router's Internal Memory  
Titan (KN-1812) example [link](https://destek.keenetic.com.tr/titan/kn-1812/tr/18482-installing-opkg-entware-in-the-router-s-internal-memory.html).
  
## === If using a USB drive (external storage) ===
User Manual / Management / OPKG / Installing the Entware Repository on a USB Drive  
Titan (KN-1812) example [link](https://destek.keenetic.com.tr/titan/kn-1812/tr/20980-installing-the-entware-repository-on-a-usb-drive.html).
  
One important point at this stage: install the OPKG Entware package manager that matches your router's CPU architecture. If you follow the online manual for your device as I recommended, the link to the correct package for your CPU architecture will be provided there. I will list the three CPU architectures below for reference (you can find your device's CPU architecture in its user manual):
  
- aarch64  
- mips  
- mipsel

In addition, if you cannot find it and are wondering where to look — while connected via SSH, type `show version` and the device architecture will appear in the first few lines.

<img src="/docs/images/KZM7.jpeg" width="800">
  
For more detailed information about OPKG, refer to the following section of your online user manual:  
User Manual / Management / OPKG / OPKG Component Description  
Titan (KN-1812) example [link](https://destek.keenetic.com.tr/titan/kn-1812/tr/42407-opkg-component-description.html).
  

# SCRIPT INSTALLATION
  
For installation you will need an SSH/Telnet client on your PC or mobile device. PuTTY is recommended for PC, and Termius for mobile.
  
- PC — [Download PuTTY](https://putty.org/index.html)
  
- Mobile — Download Termius:
  - [Android](https://play.google.com/store/apps/details?id=com.server.auditor.ssh.client)
  - [iOS](https://apps.apple.com/us/app/termius-modern-ssh-client/id549039908)
  
## === Steps to perform via SSH using PuTTY / Termius ===
  
In the application, enter the IP address you use to access your router's web interface — usually 192.168.1.1. For the port, enter 22 or 222 depending on your setup. (If you have not yet installed the "SSH Server" component under Keenetic's "Component Options", the default OPKG port is 22. If you have already installed the SSH component, the default OPKG port is 222.)

You can also connect to your device via Telnet. In that case, set the port to 23. Once connected (using your device username and password), enter the following in the command line:

```bash
(config)> exec sh
```

This switches you to the Entware BusyBox shell.

<img src="/docs/images/KZM4.png" width="800">

After clicking Open, the login screen appears. Enter the defaults:
  
login as: root  
root@192.168.1.1's password: keenetic
  
*(Note: The password is not displayed as you type — the screen appears unresponsive. Keep typing and press Enter to confirm.)* The command prompt will appear after a successful login.
  
<img src="/docs/images/KZM5.png" width="800">

- To change the default Keenetic password, enter the following command:
  
```
~ # passwd
```
  
The system will first ask for the old password (keenetic). Then enter and confirm your new password.
  
## === Installing the Keenetic Zapret2 Manager script ===

**Method 1 (quick):**  
Type the following commands one by one at the command prompt in PuTTY / Termius and press Enter after each.

First, update your system packages:

```bash
opkg update && opkg upgrade
```

Then download the script:

**With wget:**

```bash
wget --no-check-certificate -O /opt/lib/opkg/keenetic_zapret2_manager.sh \
  https://raw.githubusercontent.com/RevolutionTR/keenetic-zapret2-manager/main/keenetic_zapret2_manager.sh
chmod +x /opt/lib/opkg/keenetic_zapret2_manager.sh
/opt/lib/opkg/keenetic_zapret2_manager.sh
```

> ⚠️ **Note:** On some devices the default `wget` does not support HTTPS. If you receive a `HTTPS support not compiled in` error, first run:
> ```
> opkg install wget-ssl
> ```
> Then retry the wget command.

**Or with curl:**

If curl is not installed, please install it first:

```bash
opkg update && opkg install curl
```

```bash
curl -fsSL https://raw.githubusercontent.com/RevolutionTR/keenetic-zapret2-manager/main/keenetic_zapret2_manager.sh \
-o /opt/lib/opkg/keenetic_zapret2_manager.sh
chmod +x /opt/lib/opkg/keenetic_zapret2_manager.sh
/opt/lib/opkg/keenetic_zapret2_manager.sh
```

---

**Alternative Installation** *(for users experiencing certificate errors or copy/paste issues)*

First, update your system packages:

```bash
opkg update && opkg upgrade
```

Then run each command separately:

```bash
wget --no-check-certificate -O /opt/lib/opkg/keenetic_zapret2_manager.sh https://raw.githubusercontent.com/RevolutionTR/keenetic-zapret2-manager/main/keenetic_zapret2_manager.sh
```

```bash
chmod +x /opt/lib/opkg/keenetic_zapret2_manager.sh
```

```bash
/opt/lib/opkg/keenetic_zapret2_manager.sh
```

Once the process is complete, you can launch the installed script by typing `kzm2`, `KZM2`, `kzm` ,`KZM` or `keenetic-zapret2` at the command prompt and pressing Enter.


<img src="/docs/images/KZM2_Main_Menu.png" width="800">

---

## Recommended Settings

<img src="/docs/images/HealthMon_EN.png" width="800">

---
  
**Method 2 (classic):**  
Download the Keenetic Zapret2 Manager script — developed by @Revolution_TR on DH — from the GitHub link.
  
Log in to your router's web interface and use the file manager to copy the downloaded `keenetic_zapret2_manager.sh` file to `lib/opkg` on your router's internal storage.
  
Using PuTTY on PC or Termius on mobile, run the commands to grant execute permission and then launch the script. (Recent updates to the script make the permission step unnecessary — the script grants its own execute permission. Additionally, even if the file is copied to the wrong location, the script installs itself in the correct place.)
  
Commands:  

First, update your system packages:

```bash
opkg update && opkg upgrade
```

Grant execute permission:  
```
chmod +x /opt/lib/opkg/keenetic_zapret2_manager.sh
```
  
Run:  
```
/opt/lib/opkg/keenetic_zapret2_manager.sh
```
  
Once the process is complete, you can launch the installed script by typing `kzm2`, `KZM2`, `kzm` , `KZM` or `keenetic-zapret2` at the command prompt and pressing Enter.
  

For the full usage guide for Keenetic Zapret2 Manager, visit the developer's GitHub page.
  


Thank you for reading — I hope this has been a useful resource.

Prepared and compiled by  
- **[@tayaydin](https://forum.donanimhaber.com/profil/173164)**


## Sources used in preparing this guide:
- **[Keenetic Support](https://destek.keenetic.com.tr/?lang=tr)**  
- **[Keenetic Zapret2 Manager GitHub page](https://github.com/RevolutionTR/keenetic-zapret2-manager)**    
