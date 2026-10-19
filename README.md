# 🍏 TKIETN-AUTH iOS Dylib Builder

Dự án tự động biên dịch thư viện xác thực bản quyền **`tkietn_auth.dylib`** (ARM64 iOS) cho Free Fire iOS và các ứng dụng mod game qua **GitHub Actions** (hoàn toàn miễn phí, không cần máy Mac).

---

## 🚀 Hướng Dẫn Build Qua GitHub Actions (1 Phút)

### Bước 1: Tạo Repository Trên GitHub
1. Truy cập [github.com/new](https://github.com/new).
2. Đặt tên Repository: `tkietn_auth_builder` (hoặc tên tùy thích).
3. Chọn chế độ **Public** (để dùng miễn phí runner macOS không giới hạn phút) hoặc **Private**.
4. Bấm **Create repository**.

### Bước 2: Tải Toàn Bộ Thư Mục Lên GitHub
Đại ca có thể:
- Dùng giao diện web: Bấm **Add file** -> **Upload files** -> Kéo toàn bộ thư mục này (bao gồm cả thư mục ẩn `.github/workflows/build.yml`) thả vào GitHub rồi bấm **Commit changes**.
- Hoặc dùng Git:
  ```bash
  git init
  git add .
  git commit -m "feat: tkietn_auth_ios native dylib"
  git branch -M main
  git remote add origin https://github.com/<tai_khoan_dai_ca>/tkietn_auth_builder.git
  git push -u origin main
  ```

### Bước 3: Nhận File `tkietn_auth.dylib`
1. Vào tab **Actions** trên GitHub.
2. Sẽ thấy workflow **Build TkietnAuth iOS Dylib** đang chạy (màu vàng) -> Chờ khoảng 30-45 giây chuyển sang màu xanh lá (Success).
3. Bấm vào lượt chạy đó, cuộn xuống phần **Artifacts** -> Tải file **`tkietn_auth_dylib.zip`** về.
4. Giải nén được file: **`tkietn_auth.dylib`**.

---

## 🛠️ Bước Tiếp Theo (Inject Vào IPA)
Sau khi có file `tkietn_auth.dylib`:
1. Copy file `tkietn_auth.dylib` vào thư mục `Downloads` của Đại ca.
2. Chạy công cụ **`InjectTkietnAuth.exe`** (đã chuẩn bị sẵn trên máy) để nạp thẳng dylib vào `tkietn.ipa`.
3. Cài file IPA lên iPhone/iPad (qua TrollStore hoặc Sideloadly) và tận hưởng!
