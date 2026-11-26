# Süpürgeç — macOS Bakım, Temizlik ve Sistem Stüdyosu

> **Alpha Sürüm 0.1** · *Ensar Gemici katkılarıyla*

CleanMyMac tarzı koyu arayüze sahip, arka planda sıfıra yakın kaynak tüketen yerel (**SwiftUI + AppKit**) macOS bakım, optimizasyon ve sistem izleme uygulaması.

## Özellikler
- **Akıllı Tarama:** Tek tuşla Sistem Çöpü, Hız bakımı ve Başlangıç servislerini analiz edip uygular.
- **Sistem Çöpü:** Kullanıcı önbellekleri, günlükler, Xcode (`DerivedData`, `DeviceSupport`), geliştirici önbellekleri (`npm`, `Gradle`, `pip`, `bun`), uygulama durumları, Mail ekleri ve Çöp Kutusu temizliği + *Ayrıntıları İncele* görünümü.
- **Uygulama Kaldırıcı:** Uygulamaları `~/Library` altındaki tüm gizli destek/önbellek/tercih kalıntılarıyla birlikte kaldırır veya **Uygulamayı Sıfırla** modunda çalıştırır.
- **Optimizasyon:** Sade Türkçe açıklamalar ve öneri rozetleriyle başlangıç servislerini yönetir; alt süreçleri ana uygulamaları altında toplayarak gerçek Mac CPU yüküne göre sıralar.
- **Bakım & Tek Seferlik Yetki:** RAM boşaltma (`purge`) ve DNS önbelleği sıfırlama için şifrenizi yalnızca ilk seferde ister; sonraki kullanımlarda şifresiz çalışır.
- **Kişiselleştirilebilir Menü Çubuğu Monitörü:** Üst bara CPU, RAM (`%` veya `GB`), Ağ hızı ve Disk ekleyebilme; tıklandığında Bellek, İşlemci ve Ağ detay sayfaları + dahili **Hız ve Bufferbloat (RPM) Testi**.
- **Canlı Öz Kaynak İzleyici:** Süpürgeç'in kendi CPU, RAM, GPU ve Disk G/Ç kullanımını uygulama içinden anlık takip edebilme.

---

## Başka Bir Mac'e İndirip Kurma

### Yöntem 1: Homebrew ile Tek Satırda Kurulum (En Kolay — Önerilen)
Homebrew kurulu herhangi bir Mac'te Terminal'e şu komutu yapıştırmanız yeterlidir (`.dmg` indirilir, **Uygulamalar** klasörüne kurulur ve Gatekeeper engeli otomatik kaldırılır):

```bash
brew tap skyeso/tap && brew trust skyeso/tap && brew install --cask skyeso/tap/supurgec
```

Güncellemek için `brew upgrade --cask supurgec`, kaldırmak için `brew uninstall --cask supurgec` komutunu kullanabilirsiniz.

### Yöntem 2: Hazır DMG Paketi ile Elle Kurulum (Derleme Gerekmez)
1. Bu deponun **Releases** sayfasından en güncel `Supurgec-v0.1-alpha-macOS.dmg` (veya `.zip`) dosyasını indirin.
2. `.dmg` dosyasını açıp **Süpürgeç** simgesini **Applications (Uygulamalar)** klasörüne sürükleyin.
3. Apple Developer sertifikası olmadan yerel imzalandığı için ilk açılışta macOS Gatekeeper uyarısı çıkarsa Terminal'de bir kez şu komutu çalıştırın:

```bash
xattr -cr "/Applications/Süpürgeç.app"
open "/Applications/Süpürgeç.app"
```

### Yöntem 3: Kaynak Koddan Tek Komutla Kurulum
Xcode Command Line Tools (`xcode-select --install`) kurulu bir Mac'te:

```bash
git clone https://github.com/skyeso/supurgec-macos.git
cd supurgec-macos
chmod +x build.sh install.sh
./install.sh
```

`./install.sh` uygulamayı otomatik derler, `/Applications/Süpürgeç.app` konumuna kopyalar ve başlatır.
