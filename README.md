# CALLSHARE HYBRID R1 — BLE GATT control + Wi‑Fi R2 PCM

**Durum:** İlk hibrit kaynak entegrasyonu / R1. Kaynaklar statik olarak kontrol edildi; Android SDK ile APK, Xcode ile IPA burada derlenmedi ve cihazda doğrulanmadı. Bu paket mevcut çalışan sistemin üzerine doğrudan kurulmuş/kanıtlanmış final sürüm değildir.

## Mimari

- **BLE GATT:** gelen çağrı sinyali, CallKit tetikleme, cevaplama/kapatma, DTMF, iPhone'dan GSM araması komutu, J7/iPhone IPv4 duyurusu, GSM OFFHOOK olayı ve SMS bildirimi.
- **Wi‑Fi UDP R2:** çağrı kontrolü değil, yalnızca 48 kHz stereo S16_LE PCM ses taşıma. Mevcut `J7WV` paket biçimi değişmedi: her 20 ms / 3840-byte PCM çerçevesi 3 adet 1280-byte ses parçasına bölünür; her datagram 20-byte header + 1280-byte PCM = 1300 byte.
- **CallKit:** BLE'den gelen çağrı olayında derhal bildirilir; Wi‑Fi IP/ses hazır olmasını beklemez. Ses motoru, CallKit ses oturumu aktif ve J7 gerçek GSM `OFFHOOK` bildirimi geldikten sonra açılmaya çalışır.
- **Dinamik IP:** iPhone IP'si BLE özel uzantısı `0xE7` üzerinden J7'ye gider; J7 IP'si `0xE6` üzerinden iPhone'a gider. Android yerel köprüsü yeni peer'i native Core'a loopback UDP `J7WP + IPv4` olarak iletir.
- **Ses kapısı:** iPhone BLE `0x0F`/`0x10` ile ses açma/kapatma talebi gönderir. Android Core'a loopback `J7WE1`/`J7WE0` gönderilir. Core başlarken varsayılan kapalıdır ve aktifken 30 saniye kontrol yenilenmezse kapatır.

## Uygulama uzantıları (yalnızca CALLSHARE Android peer için)

| Opcode | Yön | Anlam |
|---|---|---|
| `0xE5` | J7 → iPhone | SMS olayı (`{"from":"…","body":"…"}` JSON) |
| `0xE6` | J7 → iPhone | J7 özel IPv4 adresi (ASCII) |
| `0xE7` | iPhone → J7 | iPhone özel IPv4 adresi (ASCII) |
| `0xE8` | J7 → iPhone | Android Telephony `OFFHOOK` bildirimi; karşı tarafın cevapladığını tek başına kanıtlamaz |

Bu özel opcode'ları stok IKOS K7/BLE cihazlarına göndermeyin. Bu protokol iki CALLSHARE eşleşik uygulaması içindir.

## Paketler

- `CALLSHARE_HYBRID_IOS_R1/` — Xcode projesi ve GitHub Actions akışı.
- `CALLSHARE_HYBRID_ANDROID_R1/` — Android kaynakları ve Windows build betiği.
- `CALLSHARE_WIFI_CORE_R2_HYBRID/` — Android ARMv7 native Core kaynağı, NDK build betiği ve güvenli dağıtım betiği.

## Derleme/dağıtım sırası

1. Windows PC'de `CALLSHARE_WIFI_CORE_R2_HYBRID/BUILD_R2_FRAGMENTED.bat` çalıştırın. Android NDK `C:\Android\sdk\ndk\25.2.9519653` altında beklenir.
2. `CALLSHARE_WIFI_CORE_R2_HYBRID/DEPLOY_CORE_TO_J7.bat` ile yeni Core'u `/data/local/tmp/j7_wifi_voice_core_R2_HYBRID` konumuna kopyalayın. Betik mevcut HAL'i değiştirmez ve Core'u el ile başlatmaz.
3. Android kaynak klasöründe `build.bat` çalıştırın. JDK 17, Android SDK Platform 35/Build Tools 35.0.0 ve **orijinal imza anahtarınız** gerekir. İmza anahtarı güvenlik nedeniyle pakete dahil değildir. Aynı imza anahtarı olmadan çalışan uygulamayı güncelleme olarak kuramazsınız; mevcut APK'yı kaldırmayın.
4. iOS proje dosyalarını GitHub deposunun köküne kopyalayın. Mevcut imzalı IPA üreten workflow'unuz varsa imzalama adımlarını koruyun; bu paketteki örnek workflow **unsigned IPA** üretir. Sertifika/özel anahtarları git deposuna eklemeyin.
5. Önce yeni Core'un J7 logunu kontrol edin, ardından Android ve iOS uygulamalarını kurup gelen çağrı, cevap, kapatma, arama başlatma, IP değişimi ve iki yönlü ses testlerini tek tek yapın.

## Güvenli geçiş notları

- Yeni Core dosyası runnable olarak bulunmadığında Android `WifiCoreSupervisor` eski `j7_wifi_voice_core_R2_FRAGMENTED_TEST` sürecini öldürmez. Yeni dosya kurulduktan sonra uygulama Core'u denetimli şekilde başlatır. **Eski ve yeni Core'u aynı anda elle çalıştırmayın:** ALSA cihaz paylaşımı çakışabilir.
- Aktif R10 Debug HAL (`/system/lib/hw/audio.primary.universal7870.so`) değiştirilmemelidir. IPA/APK içerisindeki herhangi bir HAL kopyasını flash etmeyin.
- Core, sesin ağ üzerinden gönderimini kapalı çağrı kapısında durdurur; ancak R1 native Core ALSA capture PCM cihazını açık tutar ve okuduğu örnekleri ağdan göndermez. İstenirse sonraki iyileştirmede idle halde ALSA capture/playback aç-kapat yapılır.
- Android GATT server, telephony callback ve SMS forwarding bu R1'de halen `MainActivity` yaşam döngüsüne bağlıdır. Uygulama süreci öldürülürse “her durumda daima bağlı kalır” garantisi yoktur. Üretim aşamasında bunlar uygun foreground service'e taşınmalı; Android arka plan başlangıç kısıtları gözetilmelidir.
- SMS metni R1 legacy GATT framing limiti için 24 byte gönderici / 72 byte gövdeyle kısaltılır. Tam SMS'ler için sonraki sürümde parçalı uygulama mesajı çerçevesi gerekir.
- `0xE8 OFFHOOK`, gelen/çıkan GSM çağrı kanalına geçildiğini bildirir. Android `CALL_STATE_OFFHOOK`, giden aramada karşı tarafın cevap verdiği anlamına gelmeyebilir. CallKit bağlantı zamanı gerçek arama durumuyla ayrıca test edilmelidir.
- **İki yönlü GSM sesin tamamı hâlâ cihaz üzerinde doğrulanmalı.** iPhone mikrofonu → Wi‑Fi UDP → J7 ALSA playback yolunun gerçek GSM uplink'ine ulaştığı bu kaynak incelemesiyle kanıtlanmış değildir. J7 mikrofonunun GSM karşı tarafa anlaşılır ses ilettiğine dair önceki kullanıcı testi bundan farklıdır.

## Statik doğrulamalar

- Swift kaynakları: `swiftc -frontend -parse` başarılı.
- C++ Core: host `g++ -fsyntax-only` başarılı; yalnızca TinyALSA `pcm_read/pcm_write` deprecation uyarıları.
- AndroidManifest: XML parse başarılı.
- Bu kontroller tam Android/Xcode derlemesi veya cihaz testi yerine geçmez.
