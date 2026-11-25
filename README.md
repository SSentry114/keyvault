# reading_session_app

App Flutter (chỉ iOS) đóng vai trò "vỏ" — toàn bộ ruột app đến từ package
[`user_screen`](https://github.com/vndn-appbuilder-team3/Reading-Session.git) kéo trực tiếp từ GitHub.

Reading Session: theo dõi phiên đọc sách, tủ sách, mục tiêu và thống kê. Hoạt động offline hoàn toàn (SQLite cục bộ).

## Cấu trúc

- `pubspec.yaml` — khai báo dependency git tới repo lib
- `lib/main.dart` — toàn bộ code của project này: fetch remote config
  (`<base>/<bundleId>/{ios|android}.json`, timeout 5s, lỗi thì bỏ qua) rồi
  `runApp(const UserScreen())`. Đổi endpoint bằng
  `--dart-define=CONFIG_BASE_URL=https://...`
- `ios/` — cấu hình iOS (bundle id `com.app.build.timer.stack`, tên hiển thị `TimerStack`, min iOS 15.6, app icon)

Không có code nghiệp vụ nào trong project này.

## Chạy

```bash
flutter pub get
flutter run -d <ios-simulator>
```

## Build

```bash
flutter build ios --release
```

## Cập nhật lib

Lib được pin theo commit trong `pubspec.lock`. Muốn lấy code mới nhất của nhánh `main`:

```bash
flutter pub upgrade user_screen
```
