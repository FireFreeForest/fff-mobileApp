<p align="center">
  <img src="docs/logo.png" alt="Logo Fire Free Forest" width="160">
</p>

# Fire Free Forest Mobile

Aplikasi Android Flutter untuk pemantauan deteksi dini kebakaran hutan. Aplikasi terhubung ke backend Fire Free Forest melalui REST API dan WebSocket, menampilkan status node di peta, peringatan realtime, analitik, riwayat event, kontrol pompa, dan menerima push notification dengan suara khusus per jenis alert.

- Nama aplikasi: **Fire Free Forest**
- Package Android: `org.firefreeforest`
- Nama package Dart: `firefreeforest`

## Fitur

- Login, sesi JWT, dan penyimpanan token aman.
- Peta status node dengan filter risiko dan status online/offline.
- Daftar node, detail telemetri, grafik asap, dan kontrol pompa manual.
- Analitik risiko, ranking node, dan riwayat event.
- Provisioning node baru melalui SoftAP perangkat.
- Update realtime melalui WebSocket.
- Push notification FCM dan notifikasi lokal dengan channel/suara per jenis event.
- Pengaturan server backend saat mode debug; server produksi di-bake saat build release.

## Kebutuhan

- Flutter dengan Dart SDK `^3.13.5`.
- Android SDK dan perangkat/emulator Android.
- Backend Fire Free Forest berjalan.
- Project Firebase dengan `android/app/google-services.json`.
- Untuk build release: keystore release dan konfigurasi FCM backend.

## Menjalankan Aplikasi

```bash
flutter pub get
flutter run
```

Default API untuk emulator Android adalah `http://10.0.2.2:8080`. Untuk perangkat fisik, gunakan IP LAN mesin backend:

```bash
flutter run --dart-define=API_BASE_URL=http://192.168.1.12:8080
```

Konfigurasi build-time lain:

| Variable | Default | Fungsi |
| --- | --- | --- |
| `API_BASE_URL` | `http://10.0.2.2:8080` | Base URL REST API dan WebSocket |
| `PROVISIONING_BASE_URL` | `http://192.168.4.1` | Alamat SoftAP perangkat untuk provisioning |
| `REGION_LABEL` | `Wilayah pemantauan` | Subtitle wilayah pada layar analitik |
| `ALLOW_SERVER_SWITCH` | `true` di debug, `false` di release | Menampilkan menu ganti server backend |

Di debug, server bisa diganti dari layar login atau pengaturan. Di release, nilai `ALLOW_SERVER_SWITCH` default `false`, sehingga URL hasil build dipakai langsung dan menu ganti server disembunyikan.

## Build Release

```bash
flutter build apk --release \
  --dart-define=API_BASE_URL=https://api.domain.com

# Untuk Play Store
flutter build appbundle --release \
  --dart-define=API_BASE_URL=https://api.domain.com
```

Build release memakai `android/key.properties` jika tersedia. Salin `android/key.properties.example`, isi path keystore dan password, lalu pastikan file tersebut tidak masuk repository. Tanpa file itu, build tetap berjalan tetapi memakai signing debug dan tidak layak untuk distribusi produksi.

File `android/app/src/main/res/raw/keep.xml` wajib dipertahankan. File ini mencegah resource shrinker release menghapus `notif_fire.ogg`, `notif_smoke.ogg`, dan `notif_sensor_error.ogg`.

## Notifikasi

Worker backend menentukan channel dan sound FCM. Aplikasi juga membuat channel yang sama untuk notifikasi lokal saat aplikasi di foreground.

| Event | Channel | Nama channel | Sound |
| --- | --- | --- | --- |
| `FIRE_DETECTED` | `fire_alerts_fire` | Kebakaran | `notif_fire` |
| `SMOKE_DETECTED`, `TEMPERATURE_HIGH`, `SOIL_DRY` | `fire_alerts_warning` | Peringatan | `notif_smoke` |
| `SENSOR_ERROR`, `DEVICE_OFFLINE` | `fire_alerts_error` | Error sensor | `notif_sensor_error` |

`DEVICE_OFFLINE` sengaja memakai channel dan suara error sensor. File suara berada di `android/app/src/main/res/raw/` dalam format OGG mono 44.1 kHz.

Catatan:

- Channel Android bersifat immutable setelah pertama kali dibuat. Jika sound channel diubah, hapus data aplikasi atau uninstall lalu install ulang agar channel dibuat kembali.
- Izin `POST_NOTIFICATIONS` diperlukan pada Android 13+.
- Jika suara tidak terdengar, periksa mode ringer, volume notifikasi, dan mode DND perangkat.
- Default channel FCM di `AndroidManifest.xml` adalah `fire_alerts_warning`; backend tetap mengirim channel spesifik per event.

## Warna dan Tema

Warna utama **tidak ditulis langsung di widget**. Semua warna palette dan warna semantik terpusat di:

```text
lib/core/theme/app_colors.dart
```

Gunakan variable `AppColors`, bukan literal `Color(0x...)`:

```dart
Container(
  color: AppColors.surface,
  child: Text(
    'Status node',
    style: TextStyle(color: AppColors.textPrimary),
  ),
)
```

Untuk transparansi, turunkan alpha dari variable yang ada:

```dart
color: AppColors.primary.withValues(alpha: 0.14)
```

Konfigurasi komponen Material (scaffold, input, tombol, navigation bar, divider, snackbar) ada di `lib/core/theme/app_theme.dart`. Theme memakai `ColorScheme.fromSeed(seedColor: AppColors.primary)` lalu override `primary`, `surface`, `error`, dan `outline`.

### Daftar Warna

| Variable | Hex | Penggunaan |
| --- | --- | --- |
| `AppColors.background` | `#ECE8E2` | Background scaffold dan layar |
| `AppColors.surface` | `#F6F4EF` | Card, input, navigation bar, panel |
| `AppColors.surfaceAlt` | `#FAF8F3` | Panel sekunder yang lebih terang |
| `AppColors.primary` | `#E97D40` | Warna brand, tombol utama, aksen |
| `AppColors.primaryDark` | `#BE573F` | Variasi brand yang lebih gelap |
| `AppColors.danger` | `#BE573F` | Error, bahaya, aksi destruktif |
| `AppColors.dangerSoft` | `#F4E4DB` | Background lembut untuk risiko bahaya/darurat |
| `AppColors.emergency` | `#8E3B2F` | Status darurat |
| `AppColors.textPrimary` | `#464641` | Teks utama |
| `AppColors.textSecondary` | `#76736C` | Teks sekunder dan label |
| `AppColors.textMuted` | `#97938B` | Teks muted, offline, hint |
| `AppColors.border` | `#DED9D1` | Border, divider, outline |
| `AppColors.success` | `#455849` | Status normal/online |
| `AppColors.successSoft` | `#E6EBDF` | Background lembut status normal |
| `AppColors.warning` | `#A58230` | Status waspada |
| `AppColors.warningSoft` | `#F0E9D8` | Background lembut status waspada |
| `AppColors.infoSoft` | `#FFF0E1` | Background informasi |
| `AppColors.dark` | `#292925` | Snackbar dan elemen gelap |

### Warna Status Risiko

Warna status risiko tidak dipilih manual di setiap layar. Gunakan extension di `lib/core/theme/risk_style.dart`:

```dart
final color = status.riskLevel.color;
final background = status.riskLevel.softColor;
```

| Risiko | Warna utama | Warna lembut |
| --- | --- | --- |
| `normal` | `success` | `successSoft` |
| `waspada` | `warning` | `warningSoft` |
| `bahaya` | `danger` | `dangerSoft` |
| `darurat` | `emergency` | `dangerSoft` |
| `unknown` | `textMuted` | `surface` |

Status koneksi perangkat memakai `DeviceConnectionStyle`:

- `online` → `AppColors.success`
- `offline` → `AppColors.textMuted`

Beberapa shadow/overlay transparan masih berupa literal `Color(0x...)` di widget karena hanya dipakai lokal. Jika warna tersebut dipakai ulang, pindahkan ke `AppColors` agar tetap konsisten.

## Struktur Proyek

```text
lib/
  app/                 router dan root app
  core/
    config/            API, server, dan build-time config
    network/           HTTP client dan error handling
    storage/           token aman dan pengaturan lokal
    theme/             AppColors, AppTheme, spacing, risk style
    utils/             helper format tanggal dan JSON
  data/                repository dan service data
  features/            auth, status, nodes, analytics, history, settings
  models/              model API dan telemetri
  services/            FCM, notifikasi lokal, WebSocket, realtime updater
  shared/widgets/      logo, header, card, chart, empty state
  state/               auth controller
```

## Testing

```bash
flutter analyze
flutter test
```

## Troubleshooting

- **API tidak terhubung**: emulator memakai `10.0.2.2`, perangkat fisik memakai IP LAN. Pastikan backend mendengarkan di `0.0.0.0` dan firewall mengizinkan port.
- **Notifikasi tidak bersuara**: pastikan ringer tidak silent, volume notifikasi > 0, DND off, dan izin notifikasi diberikan. Channel sound tidak berubah setelah dibuat; uninstall aplikasi untuk membuat ulang channel.
- **Sound hilang di release**: pastikan `android/app/src/main/res/raw/keep.xml` masih ada dan file OGG tidak dihapus resource shrinker.
- **Install via ADB ditolak MIUI**: matikan sementara verifier ADB, install, lalu aktifkan kembali. Gunakan `adb install -r` atau `pm install -r` dari `/data/local/tmp`.
- **Splash gelap di MIUI**: background window aplikasi memakai warna cream, tetapi animasi launch sistem MIUI dapat memakai background sendiri.
