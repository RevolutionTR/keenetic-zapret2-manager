# 🤖 Telegram Bildirimleri ve Bot – Kurulum Rehberi

Bu rehber, Keenetic Zapret2 Manager için **Telegram bildirimlerini ve iki yönlü bot kontrolünü** birkaç adımda nasıl kuracağınızı anlatır.

Telegram entegrasyonu sayesinde router'dan **anlık sistem ve Zapret2 durumu** mesajları alabilir, aynı zamanda **Telegram üzerinden router'ınızı yönetebilirsiniz**.

---

## 📌 Telegram Entegrasyonu Nedir?

KZM2'nin Telegram entegrasyonu iki bölümden oluşur:

### 1. Bildirimler (Tek Yönlü)
Router'dan Telegram'a otomatik bildirimler:
- 🚨 Zapret2 durmuş olabilir (auto-restart başarısızsa)
- ✅ Zapret2 tekrar çalışıyor
- ⚠️ CPU / RAM / Disk kullanımı yüksek
- 📌 Başlıklı ve tarih-saatli durum mesajları

### 2. Bot Kontrolü (İki Yönlü)
Telegram'dan router'a komut gönderme:
- 📊 Anlık sistem durumu sorgulama
- 🔧 Zapret2 başlatma / durdurma / yeniden başlatma
- 📡 Bağlı cihazları görüntüleme
- 📶 WiFi açma / kapatma
- 🔁 Router yeniden başlatma
- 📋 Log görüntüleme

> Telegram entegrasyonu **opsiyoneldir**. Kurmazsanız sistem normal çalışır.

---

## 1️⃣ Telegram Bot Oluşturma

1. Telegram'da **@BotFather** ile konuşun
2. Sırasıyla şu komutları yazın:

   `/start`

   `/newbot`

3. BotFather size bir **BOT TOKEN** verecek
   (örnek: `123456:ABC-DEF...`)
4. Bu token'ı bir yere kaydedin ve **KESİNLİKLE HİÇ KİMSE İLE PAYLAŞMAYIN!**

---

## 2️⃣ Chat ID Öğrenme

1. Oluşturduğunuz bot'a Telegram'dan **en az bir mesaj gönderin** Aksi halde chatid görünmez !
2. Tarayıcıda şu adresi açın:

   `https://api.telegram.org/bot<BOT_TOKEN>/getUpdates`

   > Not: BOT_TOKEN yazarken `<>` işaretlerini kaldırarak `bot12345:KEKDK.../` gibi yazın!

3. Çıktıda aşağıdaki alanı bulun:

   `"chat": {"id": 123456789`

   Bu sayı sizin Chat ID'nizdir.

---

## 3️⃣ Script Üzerinden Kaydetme

Keenetic Zapret2 Manager'ı çalıştırın ve **Telegram Bildirim Ayarları** menüsüne gidin (Menü 15).

Buradan:
1. **Token/ChatID Kaydet-Guncelle** seçeneğiyle Bot Token ve Chat ID'yi girin
2. **Test Mesajı Gonder** seçeneğini kullanın

Test mesajı Telegram'a gelirse bildirim kurulumu tamamdır ✅

---

## 4️⃣ Telegram Bot Etkinleştirme (İki Yönlü Kontrol)

Bot kontrolünü aktif etmek için:

1. Menü 15 → **4) Telegram Bot Yönetimi**'ne gidin
2. **1) Botu Etkinleştir / Ayarla** seçeneğini seçin
3. Polling aralığını girin (varsayılan: 5 saniye)
4. Bot başarıyla başlarsa `Bot AKTIF - 2 yonlu haberlesme calisiyor` mesajı görünür

Bot etkinleştirildikten sonra router yeniden başlasa bile **otomatik olarak başlar** (`/opt/etc/init.d/S98zkm_telegram` üzerinden).

---

## 📱 Bot Komutları

Bot etkin olduğunda Telegram'da `/` yazarak komut listesine ulaşabilirsiniz:

| Komut | Açıklama |
|-------|----------|
| `/start`, `/menu` | Ana menüyü açar |
| `/durum`, `/status` | Anlık sistem durumunu gösterir |
| `/zapret2` | Zapret2 yönetim menüsüne gider |
| `/sistem`, `/system` | Sistem ve router menüsüne gider |
| `/kzm2` | KZM2 yönetim menüsüne gider |
| `/help`, `/yardim` | Detaylı yardım mesajı gösterir |

> **Not:** Komutlar sadece tanımlanan Chat ID'den kabul edilir.

---

## 🔒 Güvenlik

- Bildirimler ve komutlar **sadece tanımlanan Chat ID'ye** gönderilir / kabul edilir
- Bot, Chat ID doğrulaması yaparak yetkisiz erişimi engeller
- Bot Token'ı **kimseyle paylaşmayın** — token'a sahip olan bot'u kontrol edebilir

---

## ❓ Sık Sorulan Sorular

**Telegram zorunlu mu?**
Hayır. Ayarlamazsanız sistem normal çalışır.

**Reboot sonrası tekrar ayar yapmam gerekir mi?**
Hayır. Bot Token, Chat ID ve bot otomatik başlatma kalıcıdır. Router yeniden başladığında bot da otomatik başlar.

**Telegram'dan komut göndererek router'ı yönetebilir miyim?**
Evet. v26.3.3 itibarıyla Telegram **çift yönlü** çalışmaktadır. Bot etkinleştirildiğinde `/durum`, `/zapret2`, `/sistem` gibi komutlarla ve inline butonlarla router'ı yönetebilirsiniz.

**Bot kapanırsa ne olur?**
HealthMon aktifse `HM_TGBOT_WATCHDOG=1` ayarıyla bot her döngüde kontrol edilir ve çökmüşse otomatik yeniden başlatılır.

**Komut listesi (`/`) Telegram'da görünmüyor?**
Bot ilk başladığında komut listesini Telegram'a otomatik kaydeder. Görünmüyorsa uygulamayı tamamen kapatıp açın (Telegram önbelleği temizlenir).

**Loglar disk doldurur mu?**
Hayır. Loglar `/tmp` altında tutulur, boyut sınırı aşılınca otomatik kırpılır.

---

## 🧪 Sorun Giderme

**Test mesajı gelmiyor**
- Bot Token doğru mu?
- Chat ID doğru mu?
- Bot'a en az bir mesaj gönderdiniz mi?

**Bildirim gelmiyor ama test çalışıyor**
- Health Monitor açık mı? (Menü 16)
- Zapret2 gerçekten durmuş durumda mı?

**Bot komutlarına yanıt vermiyor**
- Bot etkin mi? (Menü 15 → Bot Yönetimi)
- Bot'un çalıştığını `/tmp/zkm_telegram_bot.pid` dosyasından kontrol edin
- `tail -20 /tmp/zkm_telegram_bot.log` ile log'a bakın

**Ana banner'da `Telegram Bot : KAPALI` görünüyor**
- `TG_BOT_ENABLE=1` ayarlıysa ama bot çalışmıyorsa: Menü 15 → Bot Yönetimi → Botu Yeniden Başlat
