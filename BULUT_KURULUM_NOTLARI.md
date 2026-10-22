# SS OIL — Bulut ve yakıt stok yapılandırması

Android Ayarlar bölümünde yerel API adresi/erişim anahtarı, Supabase proje URL, **publishable/anon** anahtarı, tablo yolları, istasyon kimliği, bağlantı modu, senkronizasyon aralığı, zaman aşımı, yakıt ürün eşleştirmesi ve yakıt stok girişleri düzenlenebilir. APK yeniden paketlenmeden bu değerler değiştirilebilir.

**ÖNEMLİ:** Ayarların kaydedilmesi gerçek bulut senkronizasyonunun kurulduğu anlamına gelmez. PC tarafında senkronizasyon servisi, Supabase tabloları/RLS, uzaktan güncelleme kuyruğu ve SMPS satış API uç noktası henüz tamamlanmadı. Supabase `service_role` / `secret` anahtarını Android uygulamasına girmeyin. Telefonda yalnızca RLS ile sınırlandırılmış publishable/anon anahtar kullanılmalı. Üretimde kullanıcı kimlik doğrulaması ve uygun RLS zorunludur.

SMPS Broj işlem sonunda oluşur. Aynı Broj altındaki bütün satırlar toplanıp tek bir atomik işlem olarak kaydedilmeli; işlem numarasının sıfırlanma/dönem davranışı doğrulanmalı. Satış verisinin kaynağı henüz doğrulanmadığından Android ekranı gerçek satış düşümü yapmaz; bunu yapılmış gibi göstermeyin. Fuel girişleri cihazda saklanır; bulut/cihazlar arası senkronizasyon olmadan farklı telefonlarda ortak stok garantisi yoktur.
