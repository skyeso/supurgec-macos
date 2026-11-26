# Süpürgeç — Aklımızda Bulunan Fikirler ve Yol Haritası

Bu dosya, geliştirme sırasında *"aklımızda bulunsun / ileride değerlendirelim"* diye not aldığımız tüm maddeleri tutar.

---

## Aklımızdaki Maddeler (Bekleyen Fikirler)

1. **Özel Uygulama Logosu / İkon Tasarımı** *(Bekliyor)*
   - Mevcut geçici fırça ikonu yerine sıfırdan şık, 3B macOS tarzında özel bir **Süpürgeç** logosu tasarlanıp `.icns` paketinin ve GitHub/Homebrew sürümünün güncellenmesi.

2. **`Application Support` İçindeki Gizli Uygulama Önbellekleri (+ Akıllı Tarama Hız Adımı)** *(Tamamlandı ✅)*
   - Brave, Chrome, Discord, Spotify, Steam, Slack, VS Code gibi uygulamaların şifrelere/oturumlara/ayarlara dokunmadan yalnızca `~/Library/Application Support/<Uygulama>/` altındaki geçici `Cache`, `Code Cache`, `GPUCache`, `DawnCache` ve `Service Worker (CacheStorage)` klasörlerini cımbızla temizleme seçeneği (açık uygulamaları otomatik koruma kalkanıyla eklendi).
   - **Akıllı Tarama** içindeki *"Çalıştır"* adımına şifresiz **RAM Boşaltma + DNS Temizleme** eklendi.
   - *(Bonus — Tamamlandı ✅)* **Çoklu Seçmeli Kökten Kaldırıcı:** 28 noktalı derin tarama, aynı anda birden fazla uygulamayı seçip toplu silme ve `Oturum Açma Öğeleri` kalıntılarını (`lsregister -u` + `backgroundtaskmanagementd` yenilemesi + Çöp Kutusu'nda bekletmeden kalıcı imha) sıfırlama eklendi.

3. **Ağ Kartı İçinde Canlı Veri Alışverişi (Uygulama Bazlı Trafik + Grafik)** *(Bekliyor)*
   - Üst bardaki **Ağ** kartına tıklandığında (boştayken `%0` ek yükle, yalnızca ekran açıkken çalışacak şekilde):
     - O saniye hangi uygulamanın ne kadar indirme/yükleme yaptığını ikonlarıyla çoktan aza sıralı gösterme (`nettop`).
     - Son 1 dakikalık canlı İndirme (yeşil) / Yükleme (turuncu) dalga grafiği.
     - Modem (Gateway) IP, aktif DNS ve anlık modem ping (`ms`) bilgisi.

4. **3 Katmanlı Hafif Güvenlik ve Sızma Denetçisi (Virüs / Zararlı Taraması)**
   - Arka planda RAM şişirmeden çalışacak güvenlik modülü:
     - **Katman 1:** Açılış servislerinin (`LaunchAgents` / `LaunchDaemons`) dijital imzasını (`codesign`) kontrol edip `/tmp`, `/Users/Shared` veya gizli klasörlerden çalışan imzasız korsan ajanları yakalama.
     - **Katman 2:** Tarayıcılara zorla yüklenen *Managed Profile* reklam politikalarını, şüpheli DNS/Proxy yönlendirmelerini, `/etc/hosts` değişikliklerini ve `.zshrc` içine gizlenmiş zararlı komutları denetleme.
     - **Katman 3:** Bilinen Mac zararlı (Adware / Stealer) kurallarıyla `İndirilenler` taraması + yerleşik **Apple XProtect** güncellik kontrolü.

5. **İleriki Dağıtım ve Ek Modül Fikirleri**
   - İstenirse **Apple Developer ID (\$99/yıl) + Notarization** ve resmi `Homebrew/homebrew-cask` başvurusu.
   - **Büyük ve Eski Dosyalar** bulucu veya görsel disk haritası (**Space Lens**).

---

## Temiz Geri Dönüş Noktası (`checkpoint-v0.1-temiz`)

İleride yapılan bir değişiklik bozulursa şu anki sağlam çalışan sürüme tek komutla dönmek için:

```bash
cd /Users/eso/.gemini/antigravity/scratch/Supurgec
git checkout checkpoint-v0.1-temiz
./install.sh
```

Ayrıca tam çevrimdışı yedek arşivi:
`/Users/eso/.gemini/antigravity/scratch/Supurgec_Backups/Supurgec-v0.1-temiz-yedek.tar.gz`
