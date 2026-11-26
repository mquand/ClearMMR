<div align="center">

![ClearMMR](Resources/AppIcon-1024.png =160x160)

# ClearMMR

**Monitor & giải phóng RAM ngay trên Menu Bar — nhẹ, nhanh, không cần Xcode để build.**

[![Release](https://img.shields.io/github/v/release/mquand/ClearMMR)](https://github.com/mquand/ClearMMR/releases)
![Platform](https://img.shields.io/badge/macOS-13%2B-black)
![License](https://img.shields.io/badge/license-MIT-blue)

</div>

---

## Tính năng

| | |
|---|---|
| **Menu Bar hiển thị** | Icon RAM + `%` sử dụng, font `monospacedDigit` chống giật, đổi màu **vàng > 80%**, **đỏ > 90%** |
| **Popover chi tiết** | RAM đang dùng / tổng, progress bar, breakdown Active – Wired – Compressed |
| **Chỉ số hệ thống** | CPU %, Swap, dung lượng ổ đĩa trống, Uptime |
| **Top 5 process** | Theo RAM resident + cột CPU %, nút **Force Quit** từng app |
| **Giải phóng RAM** | Chạy `/usr/sbin/purge` qua `NSAppleScript` (quyền admin), thông báo macOS sau khi xong |
| **Login item** | `SMAppService` — khởi động cùng macOS |
| **Đa ngôn ngữ** | Tiếng Việt (mặc định) + English, tự theo ngôn ngữ hệ thống |
| **Nhẹ** | Cập nhật 2.5s/lần bằng `Task.sleep`, không Timer, CPU ~0% khi idle |

## Cài đặt

Tải bản mới nhất tại [Releases](https://github.com/mquand/ClearMMR/releases):

- **`ClearMMR-vX.Y.Z.dmg`** — kéo thả vào Applications (khuyến nghị)
- **`ClearMMR-vX.Y.Z.zip`** — giải nén và chạy trực tiếp

> App được **ad-hoc sign**, chưa qua notarization. Nếu macOS chặn mở
> ("damaged" / "unidentified developer"), chuột phải → **Open**, hoặc chạy:
> `xattr -dr com.apple.quarantine /Applications/ClearMMR.app`

## Giao diện

```
Menu Bar :  [chip-icon] RAM 68%
Popover  :  ┌──────────────────────────────┐
            │ Bộ nhớ đang dùng      8.2/16 GB│
            │ ████████░░░░░░░░  51%         │
            │ CPU 12%   │ Swap 1.2/2.0 GB    │
            │ Ổ trống   │ Uptime 3g 12p      │
            │ Active / Wired / Compressed   │
            │ Top ứng dụng dùng RAM         │
            │  Safari   1.2 GB  3%  [⏻]     │
            │ [ Giải phóng RAM ]            │
            │ [x] Khởi động cùng macOS      │
            │ [ Thoát ClearMMR ]            │
            └──────────────────────────────┘
```

## Cách hoạt động

| Thành phần | API |
|---|---|
| Vẽ Menu Bar item | SwiftUI `MenuBarExtra` (`.window` style) — macOS 13+ |
| Chỉ hiện Menu Bar | `LSUIElement = true` trong Info.plist |
| RAM stats | `host_statistics64(HOST_VM_INFO64)` + `hw.memsize` |
| CPU % | `host_statistics(HOST_CPU_LOAD_INFO)`, delta giữa 2 sample |
| Top process | `proc_listallpids` + `proc_pidinfo` (libproc) |
| Force Quit | `NSRunningApplication.forceTerminate()` → fallback `kill -9` |
| Giải phóng RAM | `NSAppleScript` → `/usr/sbin/purge` với admin privileges |
| Login item | `SMAppService.mainApp` |
| Thông báo | `UNUserNotificationCenter` |
| Đa ngôn ngữ | `Localizable.strings` trong `*.lproj` |

## Build từ source (không cần Xcode)

Yêu cầu duy nhất: **Command Line Tools** (`xcode-select --install`).

```bash
git clone https://github.com/mquand/ClearMMR.git
cd ClearMMR
bash scripts/build-app.sh          # → build/ClearMMR.app
open build/ClearMMR.app
```

Build universal (arm64 + x86_64), tự lấy version từ git tag gần nhất.

## CI / Release

Workflow `.github/workflows/build.yml` (runner `macos-15`):

| Trigger | Kết quả |
|---|---|
| Push tag `v*` | Build → zip + dmg → **GitHub Release** (`--generate-notes`) |
| `workflow_dispatch` | Build → upload artifact (không release) |

```bash
git tag v1.1.0 && git push origin v1.1.0   # phát hành release mới
```

## Quyền hạn

App **không dùng App Sandbox**, không entitlement — mọi API đều chạy được
với quyền user thường, ngoại trừ:

- **`purge`**: cần admin → hiện hộp thoại mật khẩu macOS mỗi lần bấm.
- **Notification & login item**: yêu cầu chạy từ `.app` bundle đã sign
  (script đã ad-hoc sign sẵn).

> `purge` chỉ thu hồi **page cache trong RAM** (kernel đọc lại từ đĩa khi
> cần) — không xóa dữ liệu, không đụng app cache trên ổ đĩa.

## Cấu trúc project

```
Sources/ClearMMR/
  ClearMMRApp.swift    # @main + MenuBarExtra + RAMGlyph icon
  RAMMonitor.swift     # logic: host_statistics, libproc, purge, login item
  ContentView.swift    # UI popover SwiftUI
Resources/
  AppIcon.icns         # icon app (tạo bởi scripts/make-icon.py)
  en.lproj/            # bản dịch English (key = tiếng Việt)
scripts/
  build-app.sh         # swiftc → universal binary → .app bundle → sign
  make-icon.py         # generate AppIcon từ Pillow
.github/workflows/
  build.yml            # CI build + release
```

## Đa ngôn ngữ

- Ngôn ngữ mặc định: **Tiếng Việt** (development region).
- English: tự động khi macOS/system language là English.
- Thêm ngôn ngữ mới: tạo `Resources/<lang>.lproj/Localizable.strings`,
  key là chuỗi tiếng Việt gốc.

## License

MIT
