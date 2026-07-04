# 📘 Keenetic Zapret2 Manager — Tam Kullanım Kılavuzu

Bu doküman betikte bulunan **tüm ana menüleri ve alt menüleri** eksiksiz şekilde açıklar.

Yeni kullanıcılar için olduğu kadar ileri seviye kullanıcılar için de referans niteliğindedir.
> [!WARNING]
> **KZM (eski sürüm) kullanıcılarına önemli not:**
> KZM2 kurulumundan **önce**, mevcut KZM kurulumunu **Menü U → KZM + Zapret Kaldır (Tam Temiz)** seçeneğiyle
> tamamen kaldırmanız gerekmektedir.
> KZM ve KZM2 aynı anda kurulu bırakılmamalıdır — iptables kuralları ve servis dosyaları çakışır.

---
## 🚀 Kurulum — 30 Saniyede Kurulum
Keenetic Zapret2 Manager, DPI engellerini minimum yapılandırma ile aşmanızı sağlar.
Kurulum düşündüğünüzden çok daha kolaydır. SSH ile router'a bağlanın ve önce sistem paketlerini güncelleyin:

```bash
opkg update && opkg upgrade
```

Ardından betiği indirin:

```bash
wget --no-check-certificate -O /opt/lib/opkg/keenetic_zapret2_manager.sh \
  https://raw.githubusercontent.com/RevolutionTR/keenetic-zapret2-manager/main/keenetic_zapret2_manager.sh
chmod +x /opt/lib/opkg/keenetic_zapret2_manager.sh
/opt/lib/opkg/keenetic_zapret2_manager.sh
```

> ⚠️ **Not:** Bazı cihazlarda varsayılan `wget` HTTPS desteklemez. `HTTPS support not compiled in` hatası alırsanız önce şunu çalıştırın:
> ```
> opkg install wget-ssl
> ```
> Ardından wget komutunu tekrar deneyin.

Veya

```bash
curl -fsSL https://raw.githubusercontent.com/RevolutionTR/keenetic-zapret2-manager/main/keenetic_zapret2_manager.sh \
-o /opt/lib/opkg/keenetic_zapret2_manager.sh
chmod +x /opt/lib/opkg/keenetic_zapret2_manager.sh
/opt/lib/opkg/keenetic_zapret2_manager.sh
```

---

**Alternatif Kurulum** *(sertifika hatası veya kopyala/yapıştır sorunu yaşayanlar için)*

Komutları tek tek çalıştırın:

```bash
wget --no-check-certificate -O /opt/lib/opkg/keenetic_zapret2_manager.sh https://raw.githubusercontent.com/RevolutionTR/keenetic-zapret2-manager/main/keenetic_zapret2_manager.sh
```

```bash
chmod +x /opt/lib/opkg/keenetic_zapret2_manager.sh
```

```bash
/opt/lib/opkg/keenetic_zapret2_manager.sh
```



---

# 🧭 Ana Menü Haritası

| Menü | Açıklama |
|--------|------------|
| 1 | Zapret2 Kur |
| 2 | Zapret2'yi Kaldır |
| 3 | Zapret2'yi Başlat |
| 4 | Zapret2'yi Durdur |
| 5 | Zapret2'yi Yeniden Başlat |
| 6 | Zapret2 Sürüm Bilgisi |
| 7 | IPv6 Sihirbaz |
| 8 | Yedek / Geri Yükle |
| 9 | DPI Profil Yönetimi |
| 10 | Betik Güncelleme |
| 11 | Hostlist / Autohostlist |
| 12 | IPSet Yönetimi |
| 13 | Rollback (Sürüm Geri Dön) |
| 14 | Tanılama Araçları |
| 15 | Telegram Bildirimleri |
| 16 | Sağlık Monitörü |
| 17 | Web Panel (GUI) |
| B | Blockcheck |
| L | Dil Değiştir (TR/EN) |
| R | Zamanlı Yeniden Başlat (Cron) |
| U | Tam Temiz Kaldırma |

---

# 🔹 Menü 1 — Zapret2 Kurulumu

Router’a Zapret2 DPI bypass motorunu kurar.

### Kurulum Adımları (otomatik):

1. OPKG paketleri kontrol edilir, eksikler yüklenir (`curl`, `ipset`, `iptables`, `cron` vb.)
2. GitHub'dan en güncel Zapret2 sürümü indirilir ve `/opt/zapret2`'e kurulur
3. **IPv6 desteği** etkinleştirilsin mi diye sorulur
4. **WAN arayüzü** seçilir (örn. `ppp0`, `eth2.1`)
5. Keenetic'e özel yapılandırmalar uygulanır
6. Varsayılan DPI profili devreye alınır: **Türk Telekom Fiber (TTL2 fake)**
7. Zapret2 başlatılır
8. Health Monitor henüz açık değilse otomatik etkinleştirilir

👉 İlk kurulumda **tek yapılması gereken budur.**

⚠️ Zapret2 zaten kuruluysa işlem yapılmaz, "Zapret2 zaten yüklü" mesajı gösterilir.

**DPI profili daha sonra Menü 9'dan değiştirilebilir.**

---

# 🔹 Menü 2 — Zapret2’yi Kaldır

Zapret2’yi sistemden güvenli şekilde kaldırır.

### Kaldırılanlar:

✔ Firewall kuralları  
✔ NFQWS2  
✔ Zapret2 servisleri  
✔ NFQUEUE / ipset kalıntıları  

### Kaldırılmayanlar:

✔ Manager (KZM2)  
✔ Health Monitor  
✔ Telegram ayarları  

👉 Zapret2’yi yeniden kurmak isteyen kullanıcılar için idealdir.

**Tam temiz kaldırma değildir.**

### Nasıl Çalışır?

Kaldırma tamamlandıktan sonra sistem otomatik olarak doğrulanır. NFQWS2 süreci, NFQUEUE kuralları, ipset setleri ve Zapret2 dizini kontrol edilir. Kalıntı tespit edilirse kullanıcıya sormadan ikinci bir temizlik geçişi otomatik çalışır.

Eğer Zapret2 zaten kurulu değilse sistem kalıntı açısından taranır:

- Kalıntı varsa → temizlemek isteyip istemediğiniz sorulur  
- Kalıntı yoksa → "Sistem temiz, kalıntı bulunamadı." mesajı gösterilir

---

# 🔹 Menü 3 — Zapret2’yi Başlat

Zapret2 servislerini aktif eder ve DPI bypass kurallarını devreye alır.

Başlatma öncesinde `/tmp/.zapret2_paused` flag dosyası temizlenir. Bu flag varken Zapret2 otomatik olarak başlatılamaz — bu flag Menü 4 tarafından oluşturulur.

---

# 🔹 Menü 4 — Zapret2’yi Durdur

Zapret2 servisini durdurur. Tüm yönlendirme/bypass işlemleri pasif olur.

`/tmp/.zapret2_paused` flag dosyası oluşturulur. Bu flag sayesinde:
- netfilter hook tetiklense bile Zapret2 yeniden başlamaz
- init.d servisi de başlatma yapmaz

⚠️ Health Monitor `HM_ZAPRET_AUTORESTART=1` olsa bile Menü 4 veya Web Panel üzerinden yapılan manuel durdurma işlemlerine **müdahale etmez** — pause flag varlığında watchdog tamamen atlanır. Sadece Zapret2'yin beklenmedik şekilde (crash, qlen) durması durumunda HealthMon devreye girer.

---

# 🔹 Menü 5 — Zapret2’yi Yeniden Başlat

Zapret2 servisini durdurur ve yeniden başlatır.

👉 Profil değişikliği, hostlist güncellemesi veya ayar değişimi yaptıysanız önerilir.

Profil değişikliği (Menü 9) zaten otomatik restart yapar — bu menü elle müdahale için kullanılır.

---

# 🔹 Menü 6 — Zapret2 Sürüm Bilgisi (Güncel/Kurulu - GitHub)

GitHub’daki güncel Zapret2 sürümünü ve cihazda kurulu sürümü karşılaştırmalı gösterir.

- **Kurulu sürüm** `/opt/zapret2/version` dosyasından okunur
- **GitHub sürümü** `bol-van/zapret2` reposunun latest release tag'inden alınır
- SHA256 hash doğrulaması yapılır — kurulu dosya bütünlüğü kontrol edilir

Yeni sürüm varsa güncelleme seçeneği sunulur.

---

# 🔹 Menü 7 — Zapret2 IPv6 Desteği (Sihirbaz)

IPv6 açık hatlarda ip6tables tarafında da kural ve yönlendirme kurulmasını sağlar.

- Mevcut IPv6 durumu otomatik tespit edilir (config dosyasındaki `--dpi-desync-ttl6` parametresine bakılır)
- Etkinleştirmek veya devre dışı bırakmak için sorulur
- Seçim mevcut durumla aynıysa hiçbir işlem yapılmaz
- Değişiklik sonrasında Keenetic'e özel yapılandırmalar yeniden uygulanır ve Zapret2 restart edilir

⚠️ Zapret2 kurulu değilse çalışmaz.

---

# 🔹 Menü 8 — Zapret2 Yedekle / Geri Yükle

Zapret2 ayarlarını yedekler veya önceki bir yedeği geri yükler.

👉 Büyük değişikliklerden önce yedek almak önerilir.

### Alt Menü:

✔ **1. IPSET Yedekle** — `/opt/zapret2/ipset/*.txt` dosyalarını `current` ve `history` klasörlerine kopyalar  
✔ **2. IPSET Geri Yükle** — `current` klasöründeki dosyalardan seçim yaparak geri yükler, Zapret2 restart edilir  
✔ **3. IPSET Yedekleri Göster** — Güncel ve son 5 geçmiş yedeği listeler  
✔ **4. Zapret2 / KZM2 Ayarlarını Yedekle** — Tüm ayar dosyalarını tek bir `tar.gz` arşivine paketler  
✔ **5. Zapret2 / KZM2 Ayarlarını Geri Yükle** — Kapsam seçimli geri yükleme:

| Kapsam | İçerik |
|--------|--------|
| Tam yedek | Her şey |
| Sadece ayarlar | config, wan_if, lang, dpi_profile |
| Sadece hostlistler | hostlist / autohostlist dosyaları |
| Sadece IPSET | ipset_clients.txt, ipset_clients_mode, ipset dizini |

✔ **6. Zapret2 Ayar Yedeklerini Göster** — Mevcut arşiv listesini gösterir

### Yedek konumları:
- IPSET: `/opt/zapret2_backups/current/` ve `/opt/zapret2_backups/history/YYYYMMDD_HHMMSS/`
- Ayar arşivi: `/opt/zapret2_backups/zapret2_settings/zapret2_settings_YYYYMMDD_HHMMSS.tar.gz`

---

# 🔹 Menü 9 — DPI Profil Yönetimi

DPI bypass yöntemini yönetir. Yapılan değişikliklerden sonra Zapret2 **otomatik olarak yeniden başlatılır.**

KZM2’de varsayılan yapı **Türk Telekom Fiber (TTL2 fake)** profilidir ve ilk kurulumda otomatik uygulanır.

### Kullanım Modları

| Mod | Açıklama |
|------|----------|
| **Varsayılan Profil** | KZM2’nin önerilen ve varsayılan DPI profili (TTL2 fake) |
| **Özel (Manuel) DPI Profili** | Gelişmiş kullanıcılar için `NFQWS2_OPT` parametrelerini manuel düzenleme |
| **Blockcheck (Otomatik)** | Blockcheck sonucuna göre en uygun DPI parametresinin otomatik uygulanması |
| **Geçiş Modu (Bypass Yok)** | ISS'de DPI olmayan veya bypass gereksiz kullanıcılar için — nfqws2 trafiği işlemeden geçirir |

### Varsayılan Profil

KZM2 ilk kurulumda aşağıdaki varsayılan profili uygular:

- **Türk Telekom Fiber (TTL2 fake)** → önerilen temel profil

Birçok kullanıcı için ek ayar gerektirmez.

### Özel (Manuel) DPI Profili

Web Panel üzerinden **HTTP / TLS / QUIC** bölümleri ayrı şekilde düzenlenebilir.

İleri seviye kullanıcılar:

- `repeats`
- `ip_ttl`
- `autottl`
- `badsum`
- `multisplit`
- farklı `lua-desync` stratejileri

gibi parametreleri değiştirebilir.

Girilen yapı önce doğrulanır. Geçersiz veya hatalı parametreler uygulanmaz.

⚠️ **Bu bölüm yalnızca ileri seviye kullanıcılar içindir. Bilinçsiz değişiklikler internet erişimini bozabilir.**

### Blockcheck (Otomatik)

Blockcheck menüsünden (B) çalıştırılan özet test sonucunda en uygun DPI parametresi otomatik bulunabilir.

Bulunan parametre:

- aktif profil olarak uygulanabilir
- sadece kaydedilebilir
- incelenebilir

Blockcheck sonucu uygulanırsa aktif durum:

- **Blockcheck (Otomatik)**

olarak görünür.

👉 Hangi ayarı kullanacağınızı bilmiyorsanız önce **Varsayılan Profil** ile başlayın, sorun yaşarsanız **Blockcheck (B)** kullanın.

### Geçiş Modu (Bypass Yok)

ISS'de DPI bulunmayan veya Zapret2'nin daha ikna edici TLS fake paketlerinin meşru bağlantıları etkilediği durumlarda kullanılır. Bu modda nfqws2 trafiği işlemeden geçirir; herhangi bir fake paket gönderilmez.

---

---

# 🔹 Menü 10 — Betik Güncelleme

KZM2 script dosyasını GitHub üzerinden günceller.

### Güvenlik Mekanizması:

| Durum | Davranış |
|--------|----------|
| Yerel < GitHub | Günceller |
| Yerel = GitHub | Atlar |
| Yerel > GitHub | Atlar (downgrade engellenir) |

### Güncelleme Akışı:

1. GitHub API'den son sürüm sorgulanır
2. Versiyon karşılaştırması yapılır
3. Güncelleme gerekiyorsa SHA256 hash doğrulaması yapılır
4. Mevcut script otomatik olarak yedeklenir: `.bak_vXX.XX.XX_YYYYMMDD_HHMMSS.sh`
5. Yedek limiti 3'tür — eskiler otomatik silinir
6. Yeni script indirilir, syntax kontrolünden geçirilir ve yerleştirilir

⚠️ GitHub'a push edilmemiş yerel değişiklikler bu işlemde kaybolur.

👉 Güncelleme sonrası sorun yaşarsanız Menü 13 (Rollback) ile önceki sürüme dönebilirsiniz.

### Güncelleme Sonrası Otomatik İşlemler:

Güncelleme başarıyla tamamlandığında aşağıdaki işlemler otomatik yapılır:

- **Telegram bot** varsa yeniden başlatılır (yeni kod ile)
- **Health Monitor** çalışıyorsa yeniden başlatılır (yeni kod ile)
- **Web Panel** kuruluysa yeni sürüm kodu ile güncellenir

Güncelleme tamamlandığında ekranda belirgin bir bildirim gösterilir ve KZM2'den çıkıp yeniden girilmesi istenir. Yeniden giriş yapılınca tüm değişiklikler aktif olur.

---

---

# 🔹 Menü 11 — Hostlist / Autohostlist (Filtreleme + Kapsam Modu)

Bu menü altında; filtreleme modu, kapsam modu, manuel hostlist ve autohostlist birlikte yönetilir.

---

## Filtreleme Modu

Zapret2'yin hangi domainlere uygulanacağını belirler.

| Mod | Açıklama |
|-----|----------|
| **Filtre Yok** | Tüm trafik işlenir, domain ayrımı yapılmaz |
| **Sadece Listedeki Domainler** | Yalnızca `zapret-hosts-user.txt` ve `zapret-hosts-auto.txt`'deki domainler işlenir |
| **Otomatik Öğren + Liste** | Hem hostlist hem autohostlist birlikte çalışır |

---

## Kapsam Modu

Bypass'ın hangi cihazlara uygulanacağını belirler.

### 🌐 Global
Tüm ağa uygulanır.

✔ Maksimum uyumluluk  
❗ Biraz daha fazla CPU  

👉 Yeni kullanıcılar için güvenlidir.

### 🧠 Akıllı Mod
Sadece engellenen hostlara uygulanır (autohostlist tabanlı).

✔ Daha az CPU  
✔ Daha temiz trafik  
✔ Daha stabil routing  

👉 Uzun vadede önerilen mod.

---

## Hostlist Yönetimi

Manuel engelli domain listesi (`zapret-hosts-user.txt`).

### Alt Menü:

✔ Domain ekle (toplu yapıştırma desteklenir)  
✔ Domain sil  
✔ Exclude (Domain): Ekle — işlenmesini istemediğiniz domainler  
✔ Exclude (Domain): Sil  
✔ Listeleri Göster  
✔ Otomatik Listeyi Temizle  
✔ User hostlist Temizle — tüm elle eklenen domainleri onayla tek seferde siler  
✔ Kapsam Modunu Değiştir (Global/Akıllı)  

👉 Autohostlist'in henüz yakalayamadığı servisleri buradan manuel ekleyebilirsiniz.

⚠️ Domain ekle/sil ve Exclude ekle/sil işlemlerinden sonra Zapret2 **otomatik olarak yeniden başlatılır.** Değişikliklerin etkili olması için ayrıca Menü 5'e girmenize gerek yoktur.

---

## Autohostlist

Engellenen servisleri otomatik öğrenir (`zapret-hosts-auto.txt`).

DPI tarafından engellenen bağlantılar tespit edildiğinde ilgili domain otomatik olarak listeye eklenir. Zamanla kişiselleştirilmiş bir bypass listesi oluşur.

**Kur → unut özelliğidir.**

⚠️ Autohostlist dolup taşmasın diye `/opt/zapret2/nfqws_autohostlist.log` 1 MB'ı aşınca son 500 satıra kırpılır (Health Monitor tarafından yönetilir).

# 🔹 Menü 12 — IPSet Yönetimi

Zapret2'yin hangi cihazlara uygulanacağını IP adresi bazında belirler.

⚠️ **DHCP desteklenmez.** Yalnızca **statik IP** atanmış cihazlar için çalışır. DHCP ile dinamik IP alan cihazların IP'si değişebileceğinden listeye eklenmemesi önerilir.

### İki Mod:

| Mod | Açıklama |
|-----|----------|
| **Tüm Ağ** | Tüm LAN cihazları için Zapret2 aktif (varsayılan) |
| **Seçili IP** | Yalnızca listedeki statik IP'ler için Zapret2 aktif |

Aktif mod menünün üstünde renk koduyla gösterilir.

### Alt Menü:

✔ IP ekle (tekli veya toplu)  
✔ IP kaldır  
✔ Aktif listeyi gör (dosya + aktif ipset üyeleri)  
✔ Listeyi temizle  
✔ Mod değiştir (Tüm Ağ ↔ Seçili IP)  
✔ No Zapret2 (Muafiyet) Yönetimi  
✔ **VPN Sunucu Subneti Ekle** — Keenetic'teki aktif VPN sunucularını otomatik tespit eder  

### Kullanım Senaryosu:

Bypass sadece şu cihazlarda çalışsın:

- Smart TV  
- Oyun konsolu  
- Apple TV  
- Android Box  

👉 Gereksiz cihazları bypass'tan çıkararak router CPU'su korunur.

---

### No Zapret2 (Muafiyet) Yönetimi

Bu listedeki IP'ler Zapret2 işleminden **muaf** tutulur. IPTV kutuları gibi Zapret2'den etkilenmemesi gereken cihazlar için idealdir.

**Çift yönlü çakışma koruması:** Bir IP No Zapret2 listesine eklendiğinde otomatik olarak `zapret2_clients` listesinden çıkarılır ve tersi de geçerlidir.

---

### VPN Sunucu Subneti Ekle

Keenetic'teki aktif VPN sunucularını otomatik tespit ederek subnet'lerini `ipset_clients` listesine ekler.

**Desteklenen VPN türleri:**
- WireGuard sunucuları (client bağlantıları otomatik olarak filtrelenir, sadece sunucu interface'leri listelenir)
- IKEv2/IPsec sunucusu
- L2TP/IPsec sunucusu

**Nasıl Çalışır:**
1. Aktif VPN sunucuları otomatik taranır ve listelenir
2. Zaten eklenmiş subnet'ler yeşil `[EKLENDİ]` etiketiyle işaretlenir
3. Seçilen subnet `/24` formatında listeye eklenir, Zapret2 restart edilir

👉 Eve VPN ile uzaktan bağlanan cihazların Zapret2 üzerinden çıkabilmesi için bu özelliği kullanın.

⚠️ IPSET modunun "Seçili IP'lere Uygula" (list) modunda olması gerekir.

# 🔹 Menü 13 — Rollback (Sürüm Geri Dön)

Script güncellemesi sonrası sorun yaşarsanız önceki sürüme dönüş yapmanızı sağlar.

### İki Yöntem:

**Yerel Depolama (Hızlı):**  
Menü 10 güncellemesi sırasında alınan `.bak_*` dosyalarından seçim yapılır. İnternet gerekmez.  
En fazla 3 yedek tutulur — eskiler otomatik silinir.  
Yedek dosya formatı: `keenetic_zapret2_manager.sh.bak_vXX.XX.XX_YYYYMMDD_HHMMSS.sh`

**GitHub'dan (Herhangi Sürüm):**  
Son 10 release tag listelenir. Seçilen sürüm GitHub raw URL'sinden indirilir.  
Mevcut dosya işlem öncesinde otomatik yedeklenir.

👉 Güncelleme sonrası sorun yaşanırsa ilk denenmesi gereken menüdür.

⚠️ Geri yükleme tamamlandıktan sonra script yeniden çalıştırılmalıdır.

---

# 🔹 Menü 14 — Ağ Tanılama ve Sistem Kontrolü

Sistem ve ağ sağlığını kapsamlı şekilde analiz eder.

### Alt Menü:

✔ Kontrol Çalıştır  
✔ OPKG Listesini Yenile  

### Kontroller:

**Ağ & DNS**  
✔ WAN bağlantı durumu ve IP adresi (IPv4/IPv6, CGNAT/NAT/Public)  
✔ DNS modu (DoH / DoT / Plain) ve güvenlik seviyesi  
✔ Aktif DNS sağlayıcıları  
✔ Yerel DNS çözümlemesi  
✔ Dış DNS (8.8.8.8) erişimi  
✔ DNS tutarlılığı  
✔ Varsayılan rota  

**Sistem**  
✔ Script konumu doğrulaması  
✔ İnternet erişimi (ping)  
✔ RAM kullanımı  
✔ CPU yük ortalaması  
✔ Disk doluluk oranı (/opt)  
✔ SoC ve WiFi çip sıcaklıkları (2.4GHz / 5GHz)  
✔ Saat / NTP senkronizasyonu  

**Servisler**  
✔ GitHub erişimi  
✔ OPKG paket durumu  
✔ Zapret2 çalışma durumu  
✔ KeenDNS durumu ve erişilebilirlik  

👉 Bir şey çalışmıyorsa ilk buraya bak.

---

---

# 🔹 Menü 15 — Telegram Bildirimleri

Telegram bot entegrasyonunu ve bildirim ayarlarını yönetir.

### Alt Menü:

✔ Token / Chat ID Kaydet-Güncelle  
✔ Test Mesajı Gönder  
✔ Ayar Dosyasını Sil (Reset)  
✔ Telegram Bot Yönetimi  

### Tek Yönlü Bildirimler:

- Servis restart / recovery bildirimleri  
- Health Monitor uyarıları (CPU/RAM/Disk/WAN vb.)  
- Güncelleme bilgilendirmeleri  

### İki Yönlü Bot (Telegram Bot Yönetimi):

Telegram üzerinden router'a komut gönderilebilir.

**Bot alt menüsü:**  
✔ Botu Etkinleştir / Ayarla (polling aralığı yapılandırılır)  
✔ Botu Devre Dışı Bırak  
✔ Botu Yeniden Başlat  

**Bot butonları ile yapılabilecekler:**  
✔ Durum — Zapret2 ve sistem durumunu gösterir (SoC/WiFi sıcaklıkları dahil)  
✔ Zapret2 — Başlat / Durdur / Yeniden Başlat / Güncelle  
✔ Sistem — KZM2 Güncelle / Router Reboot  
✔ Wifi Yönetim — 2.4GHz ve 5GHz bantlarını ağ bazında (Ev/Misafir) ayrı ayrı aç/kapat  
✔ Loglar — KZM2 Log / Sistem Log  

👉 Bot aktifken "AKTIF - 2 yönlü haberleşme çalışıyor" olarak görünür.

⚠️ Bot Token ve Chat ID doğru girilmelidir.

---

# 🔹 Menü 16 — Sağlık Monitörü

Arka planda çalışan otomasyon motorudur. Sistem sorunlarını tespit eder, bildirim gönderir ve bazı durumlarda otomatik müdahale eder.

👉 Açık tutulması **şiddetle önerilir.**

---

## [AYARLAR]

### Aralık (HM_INTERVAL)
Her kaç saniyede bir kontrol yapılacağını belirler.
- Varsayılan: `60` saniye
- Düşürülürse daha hızlı tespit, biraz daha fazla CPU kullanımı

### Heartbeat (HM_HEARTBEAT_SEC)
Her N saniyede bir Telegram'a "hâlâ çalışıyorum" mesajı gönderir.
- Varsayılan: `300` saniye (5 dakika)
- Sessiz kalan bot öldü mü diye endişelenmemek için kullanılır

### Cooldown (HM_COOLDOWN_SEC)
Aynı uyarının tekrar gönderilmeden önce beklenmesi gereken süre.
- Varsayılan: `600` saniye (10 dakika)
- Bu olmasa her 60 saniyede aynı uyarı gelirdi

### Güncelleme kontrolü (HM_UPDATECHECK_ENABLE / HM_UPDATECHECK_SEC)
KZM2 ve Zapret2 için GitHub'da yeni sürüm var mı diye periyodik kontrol yapar.
- Varsayılan aralık: `21600` saniye (6 saat)

### Oto güncelleme (HM_AUTOUPDATE_MODE)
Yeni sürüm bulununca ne yapılacağını belirler.

| Değer | Davranış |
|-------|----------|
| `0` | Güncelleme kontrolü kapalı |
| `1` | Yeni sürüm bulununca sadece Telegram bildirimi gönderir |
| `2` | Yeni sürümü otomatik kurar (varsayılan) |

⚠️ Mod 2 ileri kullanıcılar için önerilir. Otomatik güncelleme sırasında Zapret2 kısa süre duraklar.

---

## [EŞİKLER]

### CPU UYARI (HM_CPU_WARN / HM_CPU_WARN_DUR)
CPU bu yüzdeyi bu süre boyunca aşarsa uyarı gönderilir.
- Varsayılan: `%70` / `180` saniye
- Anlık sıçramalara karşı süre koruması var — kısa süreli yüksekler tetiklemez

### CPU KRİTİK (HM_CPU_CRIT / HM_CPU_CRIT_DUR)
Daha kısa sürede tetiklenen acil eşik.
- Varsayılan: `%90` / `60` saniye

### Sıcaklık UYARI / KRİTİK (HM_TEMP_WARN / HM_TEMP_CRIT)
SoC sıcaklığı belirlenen eşiği bu süre boyunca aşarsa Telegram'a bildirim gönderilir.
- Varsayılan: Uyarı `75°C` / `180` saniye, Kritik `85°C` / `60` saniye
- Varsayılan olarak **kapalı** gelir — sıcaklık sensörü olmayan cihazlarda karışıklık yaratmaması için
- Sensör bulunamazsa özellik sessizce devre dışı kalır, hata vermez
- Tek ekrandan aç/kapa, eşik ve süre birlikte yönetilir

### Disk(/opt) UYARI (HM_DISK_WARN)
`/opt` doluluk oranı bu eşiği aşarsa uyarı gönderilir.
- Varsayılan: `%90`
- USB dolan kullanıcılarda Zapret2 çalışmayı durdurabilir — erken uyarı kritiktir

### RAM UYARI (HM_RAM_WARN_MB)
Boş RAM bu değerin altına düşerse uyarı gönderilir.
- Varsayılan: `<= 40 MB`

---

## [ZAPRET2]

### Zapret2 denetimi (HM_ZAPRET_WATCHDOG)
nfqws2 process'i çalışıyor mu diye her aralıkta kontrol eder.
- `1` = aktif (varsayılan), `0` = kapalı
- Zapret2 çökmüşse 30 saniye içinde tespit edilir

### Zapret2 bekleme (HM_ZAPRET_COOLDOWN_SEC)
Zapret2 ile ilgili bildirimlerin tekrar gönderilmeden önce beklenmesi gereken süre.
- Varsayılan: `120` saniye

### AutoRes — Otomatik Yeniden Başlatma (HM_ZAPRET_AUTORESTART)
Zapret2 durduğunda HealthMon otomatik başlatma denesin mi?

| Değer | Davranış |
|-------|----------|
| `0` | Sadece bildirim gönderir, başlatmaz |
| `1` | ~30 saniye sonra otomatik başlatır **(varsayılan)** |

⚠️ **Önemli:** Menü 4 veya Web Panel ile Zapret2'yi kasıtlı durdurduğunuzda `/tmp/.zapret2_paused` flag'i oluşturulur. `AutoRes=1` olsa bile HealthMon bu flag'i görünce watchdog'u tamamen atlar — yani Zapret2 başlatılmaz. Sadece Zapret2'yin beklenmedik şekilde (crash, qlen vb.) durması durumunda HealthMon otomatik olarak devreye girer.

👉 Zapret2'yi kalıcı durdurmak istiyorsanız `AutoRes=0` olmalıdır.

### NFQUEUE kuyruk denetimi (HM_QLEN_WATCHDOG / HM_QLEN_WARN_TH / HM_QLEN_CRIT_TURNS)

**Bu ayar çok kritiktir ve çoğu kullanıcı tarafından gözden kaçırılır.**

nfqws2 process'i çalışıyor görünse de NFQUEUE kuyruğu dolup taşabilir. Bu durumda:
- Paketler işlenemiyor ve düşüyor
- İnternet yavaşlıyor veya kesiliyor
- `ps` komutu nfqws2'in çalıştığını göstermeye devam ediyor
- Kullanıcı "KZM2'de sorun var" sanıyor — oysa sorun kuyruk tıkanıklığı

HealthMon `/proc/net/netfilter/nfnetlink_queue` dosyasını okuyarak queue 300'ün anlık doluluk değerini (`qlen`) izler.

| Ayar | Açıklama | Varsayılan |
|------|----------|------------|
| `HM_QLEN_WATCHDOG` | Denetimi aç/kapat | `1` (açık) |
| `HM_QLEN_WARN_TH` | Kaç paketten sonra sayaç artmaya başlar | `50` |
| `HM_QLEN_CRIT_TURNS` | Kaç ardışık turda yüksek kalırsa restart tetiklenir | `3` |

**Örnek akış:** Kuyruk 50'yi aştı → 1. tur → 2. tur → 3. tur → Zapret2 otomatik restart → sorun çözülür, kullanıcı hiçbir şey fark etmez.

### KeenDNS curl interval (HM_KEENDNS_CURL_SEC)
KeenDNS erişilebilirlik kontrolü ne sıklıkta yapılsın.
- Varsayılan: `120` saniye
- `0` yapılırsa her döngüde kontrol edilir (eski davranış)

### Debug Modu (HM_DEBUG)
HealthMon döngüsünün iç kararlarını ayrıntılı şekilde `/tmp/healthmon_debug.log` dosyasına kaydeder.

- Varsayılan: `0` (kapalı)
- Menü 16 → 4 → 14 ile açılıp kapatılabilir
- Telegram Log menüsünden 🐛 Debug Log butonu ile de erişilebilir

Loglanan kategoriler: zapret2 watchdog kararları, WAN izleme, Telegram bot watchdog, güncelleme kontrolü GitHub API sorguları.

👉 Sorun giderme ve davranış analizi için kullanılır. Normal kullanımda kapalı bırakın.

---

## Zapret2 Restart Kayıtları

Tüm Zapret2 yeniden başlatma olayları `/tmp/healthmon.log` dosyasına yazılır:

| Kayıt | Tetikleyici |
|-------|-------------|
| `zapret2_restart \| triggered` | SSH menüsünden (Menü 3, 5, 11 vb.) |
| `zapret2_restart \| triggered (web)` | Web Panel üzerinden |
| `zapret2_restart \| triggered (ipset)` | IPSET / No Zapret2 işlemlerinden |
| `qlen_restart_ok` | NFQUEUE kuyruk dolması nedeniyle |
| `zapret2_autorestart_ok` | HealthMon watchdog tarafından |

👉 Zapret2 restart geçmişini takip etmek için: `tail -50 /tmp/healthmon.log | grep zapret2_restart`

---

## [ŞİMDİ]

Anlık sistem durumunu gösterir: CPU yüzdesi, yük ortalaması (1/5/15 dk), boş RAM, disk doluluk oranı, SoC ve WiFi çip sıcaklıkları (2.4GHz / 5GHz) ve Zapret2 durumu.

---

## Önerilen Yapılandırma

<img src="/docs/images/HealthMon_TR.png" width="800">

---

# 🔹 Menü 17 — Web Panel (GUI)

Tarayıcı üzerinden erişilebilen görsel yönetim paneli.

Varsayılan port: **8088** → `http://<router-ip>:8088`

### Alt Menü:

✔ **Web Panel Kur** — lighttpd + CGI kurulur, cron ile durum yenileme aktif edilir, iptables kuralı açılır  
✔ **Web Panel Kaldır** — lighttpd, CGI ve cron satırı temizlenir  
✔ **Web Panel Güncelle** — HTML ve CGI dosyaları güncel sürümle yeniden yazılır  
✔ **Web Panel Durumu** — lighttpd çalışıyor mu, port, dosya varlığı gösterilir  
✔ **Web Panel Aç/Kapat** — Erişimi etkinleştirir veya devre dışı bırakır (lighttpd durdurulur/başlatılır)  

### Port Değiştirme

Web panel menüsünden port numarası değiştirilebilir (1024–65535 arası). Değişiklik `/opt/etc/kzm2_gui.conf` dosyasına kaydedilir ve iptables kuralı otomatik güncellenir.

### Nasıl Çalışır?

Web panel, `/opt/var/run/kzm2_status.json` dosyasından veri okur. Bu JSON dosyası `kzm2_status_gen.sh` scripti tarafından **her dakika** cron ile yenilenir. Tarayıcıdaki dashboard ise bu veriyi 15 saniyede bir çeker — yani panel anlık değil, en fazla 1 dakika gecikmeli gösterir.

Komutlar (Zapret2 başlat/durdur, profil değiştir vb.) ise CGI üzerinden gerçek zamanlı çalışır.

### Panel İçerikleri:

| Bölüm | İçerik |
|-------|--------|
| Dashboard | Zapret2 durumu, DPI profili, CPU/RAM/Disk, HealthMon |
| Zapret2 | Başlat / Durdur / Yeniden Başlat |
| DPI | Profil seçimi |
| Hostlist | Domain ekleme/silme |
| IPSet | IP ekleme/silme, mod değiştirme |
| HealthMon | Durum izleme, yapılandırma |
| Telegram | Bot token/chat ID ayarı |
| OPKG | Paket listesi yenileme |

👉 Router'a SSH bağlantısı olmadan temel yönetim yapılabilir.

⚠️ lighttpd paketi gerektirir. Kurulum sırasında otomatik yüklenir. crond çalışıyor olmalıdır.

> [!WARNING]
> ## 🔒 Web Panel Güvenlik Notu
>
> KZM2 Web Panel yalnızca **güvenilir yerel ağ (Trusted LAN)** üzerinde kullanılmak üzere tasarlanmıştır.
>
> **Önerilmez:**
> - WAN (internet) erişimine açılması
> - Port Forward yapılması
> - Misafir (Guest) ağlarından erişim
> - IoT/VLAN gibi güvenilmeyen segmentlerden erişim
>
> Web Panel; Zapret2 yeniden başlatma, DPI profili değiştirme, hostlist/IPSET yönetimi ve sistem işlemleri gibi **yönetici seviyesinde işlemler** yapabilir.
>
> Bu nedenle yalnızca **ev/ofis içindeki güvenilir yönetim ağı** üzerinden kullanılması önerilir.
---

# 🔹 R — Zamanlı Yeniden Başlat (Cron)

Router'ı belirli saat veya günde otomatik yeniden başlatır. `ndmc -c "system reboot"` komutu ile tetiklenir.

### Alt Menü:

✔ **Mevcut zamanlamayı göster** — Kayıtlı cron satırını görüntüler  
✔ **Günlük yeniden başlatma ekle/güncelle** — Her gün HH:MM saatinde reboot  
✔ **Haftalık yeniden başlatma ekle/güncelle** — Belirli bir gün (Pzt–Paz) ve HH:MM saatinde reboot  
✔ **Zamanlamayı sil** — Cron satırını kaldırır  

### Nasıl Çalışır?

Zamanlama crontab'a `# KZM2_REBOOT` etiketiyle kaydedilir. Bu etiket sayesinde:

- Yeni zamanlama eklendiğinde eskisi otomatik değiştirilir — birden fazla satır oluşmaz
- Silme işleminde yalnızca KZM2'ye ait satır kaldırılır, diğer cron görevleri korunur

Ana menü banner'ında aktif zamanlama gösterilir:
- Günlük: `Sched.Reboot : 03:00`
- Haftalık: `Sched.Reboot : 03:00 (Paz)`

### Önerilen Kullanım

Uzun süre kesintisiz çalışan routerlarda hafızada biriken geçici dosyalar router performansını düşürebilir. Haftada bir veya iki günde bir gece yarısı reboot planlamak bu durumu önler.

👉 Telegram botu kuruluysa reboot öncesinde bildirim gönderilir.

⚠️ crond servisinin çalışıyor olması gerekir. Çalışmıyorsa menü girişinde uyarı gösterilir.

---

# 🔵 B — Blockcheck Test Menüsü

DPI testleri çalıştırır, bağlantı durumunu analiz eder ve en uygun DPI parametresini otomatik olarak tespit eder.

### Alt Menü:
✔ **1. Blockcheck Test (Otomatik DPI Profili)** — Hızlı test; DPI engelini tespit edip en uygun parametreyi önerir  
✔ **2. Blockcheck Intersection (6 domain, 15-40dk)** — 6 farklı domain üzerinde ortak çalışan stratejiyi bulur; daha güvenilir sonuç  
✔ **3. Blockcheck Tam Test (~30-45dk)** — Tüm test senaryolarını çalıştırır  
✔ **4. Test Sonuçlarını Temizle** — `blockcheck_*.txt` ve `blockcheck_summary_*.txt` dosyalarını siler  
✔ **5. Aktif DPI Profilini Dışa Aktar** — Mevcut DPI profilini ve parametrelerini dışa aktarır  

### DPI Health Score:

Özet test tamamlandığında bir skor hesaplanır (örn. `8.5 / 10`):

| Kontrol | Açıklama |
|---------|----------|
| ✔ DNS tutarlılığı | ISP DNS manipülasyonu var mı? |
| ✔ TLS 1.2 durumu | TLS 1.2 üzerinden HTTPS erişimi çalışıyor mu? |
| ⚠ UDP 443 zayıf | QUIC/HTTP3 engellenmiş veya riskli mi? |

### Otomatik DPI Akışı:

Her 3 test tamamlandığında sonuç bulunursa en uygun nfqws2 parametresi tespit edilir. Kullanıcıya karar ekranı sunulur:

| Seçenek | Açıklama |
|---------|----------|
| **[1] Uygula** | Parametre DPI profili olarak aktif edilir, Zapret2 restart edilir |
| **[2] Parametreyi İncele** | Bulunun parametreyi gösterir |
| **[3] Sadece Kaydet** | Profili değiştirmeden sadece kaydeder |
| **[0] Vazgeç** | İşlem yapılmaz |

👉 Hangi profili kullanacağınızı bilmiyorsanız veya mevcut profil çalışmıyorsa buradan başlayın.

---

# 🌐 L — Dil Değiştir (TR/EN)

Arayüz dilini Türkçe / İngilizce arasında değiştirir.

---

# 🔥 Menü U — Tam Temiz Kaldırma

⚠️ Geri alınamaz işlemdir.

Router’ı KZM2 kurulum öncesi hale getirir.

---

## İşlem Aşamaları

### ✔ 1. Zapret2 kaldırılır  
(Doğrulama ve otomatik ikinci temizlik geçişi dahil tam kaldırma rutini çalışır)

### ✔ 2. Manager kalıntıları temizlenir

Silinenler:

- Health Monitor  
- Telegram config  
- Init servisleri  
- Log dosyaları  
- State dosyaları  
- Backup dosyaları  

---

## Güvenlik Tasarımı

👉 Betik dosyası **bilerek silinmez.**

Amaç:

✔ Kullanıcının kilitlenmesini önlemek  
✔ Tekrar kopyalama ihtiyacını azaltmak  

İsteyen kullanıcı manuel silebilir.

---

---

# ⭐ ÖNERİLEN KULLANIM AKIŞI

## Yeni Kullanıcı

```
1  → Zapret2 kur
15 → Telegram bot ayarla (isteğe bağlı)
16 → Health Monitor aç
```

İnternet çalışmıyorsa:

```
B → Blockcheck Test yap → Uygula
```

---

## İleri Kullanıcı

```
11 → Filtreleme modunu "Otomatik Öğren + Liste" yap
11 → Kapsam modunu "Akıllı Mod" yap
R  → Haftalık gece yarısı reboot planla
```

---

## Sorun Giderme

```
14 → Tanılama çalıştır (DNS, WAN, Zapret2, GitHub kontrol et)
B  → Blockcheck Test → Otomatik DPI parametresi uygula
9  → Profili değiştir ve dene
14 → Hâlâ sorun varsa OPKG listesini yenile
U  → Son çare: tam temiz kaldır → 1 → yeniden kur
```

---

# 🚨 KRİTİK UYARI

Rastgele DPI ayarı değiştirmeyin.

Sorunların çoğu şunlardan kaynaklanır:

✔ ISP değişiklikleri  
✔ DNS problemleri  
✔ Yanlış profil
