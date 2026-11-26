# ClearMMR

Ứng dụng Menu Bar (LSUIElement — không hiện icon Dock) theo dõi và giải phóng RAM cho macOS 13+.

## Tính năng

- Hiển thị `% RAM` trên Menu Bar, font `monospacedDigit`, đổi màu vàng (>80%) / đỏ (>90%).
- Popover chi tiết: RAM đang dùng / tổng, progress bar, Active – Wired – Compressed (từ `host_statistics64`).
- Top 5 tiến trình ngốn RAM nhất (libproc) kèm nút Force Quit.
- Nút **Giải phóng RAM**: chạy `/usr/bin/purge` qua `NSAppleScript` với admin privileges, có thông báo macOS.
- Toggle **Khởi động cùng macOS** (`SMAppService.mainApp`) và nút **Thoát**.
- Cập nhật mỗi 2.5 giây bằng `Task.sleep` — không dùng Timer, CPU gần như 0% khi idle.

## Cấu trúc

```
Sources/ClearMMR/
  ClearMMRApp.swift   # @main + MenuBarExtra + label %RAM
  RAMMonitor.swift    # logic: host_statistics64, libproc, purge, login item, notify
  ContentView.swift   # UI popover SwiftUI
scripts/build-app.sh  # build + đóng gói .app + ad-hoc sign
.github/workflows/    # CI tự build khi push main / tag v*
```

## Build local (không cần Xcode)

Yêu cầu: Command Line Tools (`xcode-select --install`) — đã có sẵn `swiftc`.

```bash
bash scripts/build-app.sh
open build/ClearMMR.app
```

Muốn cài vào Applications:

```bash
cp -R build/ClearMMR.app /Applications/
```

> **Lưu ý toolchain:** một số bản CLT bị lỗi trùng module `SwiftBridging`
> (`redefinition of module 'SwiftBridging'`). Cách sửa:
> `sudo rm /Library/Developer/CommandLineTools/usr/include/swift/module.modulemap`
> hoặc cài lại/cập nhật CLT mới hơn.

## Quyền hạn & cấu hình

App **không dùng App Sandbox** (binary tự build, không có entitlement) nên:

- `host_statistics64`, `libproc`, `kill -9` chạy được ngay, không cần quyền gì thêm.
- `purge` cần quyền admin → `NSAppleScript ... with administrator privileges` sẽ hiện hộp thoại nhập mật khẩu macOS mỗi lần bấm.
- Notification (`UNUserNotificationCenter`) cần app chạy từ `.app` bundle đã sign. Script đã ad-hoc sign; nếu muốn notification ổn định hơn khi phát hành, sign bằng Developer ID:
  `codesign --force --deep --sign "Developer ID Application: TÊN (TEAMID)" build/ClearMMR.app`
- `SMAppService.mainApp` (login item) cũng yêu cầu chạy từ `.app` bundle; chạy `swift run` sẽ tự disable toggle này.

`LSUIElement = true` trong `Info.plist` (do script sinh ra) giúp ẩn icon khỏi Dock — chỉ hiện trên Menu Bar.

## CI / Git workflow

Workflow `.github/workflows/build.yml` chạy trên `macos-14` (có Xcode đầy đủ):

- Push lên `main` → build `ClearMMR.app`, đóng zip, upload artifact (giữ 30 ngày).
- Push tag `v1.0.0` → tự tạo GitHub Release kèm file zip.

```bash
git tag v1.0.0 && git push origin v1.0.0   # phát hành release
```

## Chạy thử không đóng gói

```bash
swiftc -O -module-name ClearMMR -o /tmp/clearmmr Sources/ClearMMR/*.swift && /tmp/clearmmr
```

Menu bar + popover hoạt động bình thường; riêng login item và notification cần `.app` bundle.
