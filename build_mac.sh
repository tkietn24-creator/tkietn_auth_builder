#!/bin/bash
set -e

echo "=== TKIETN-AUTH iOS Dylib Local Builder (macOS) ==="

SDK_PATH=$(xcrun --sdk iphoneos --show-sdk-path)
echo "[+] Using iPhoneOS SDK at: $SDK_PATH"

xcrun -sdk iphoneos clang++ -arch arm64 \
  -shared -fPIC -O3 \
  -isysroot "$SDK_PATH" \
  -miphoneos-version-min=14.0 \
  -framework Foundation \
  -framework UIKit \
  -framework Security \
  -fobjc-arc \
  tkietn_auth_ios.mm -o tkietn_auth.dylib

echo "[+] Signing tkietn_auth.dylib..."
codesign -f -s - tkietn_auth.dylib 2>/dev/null || true

echo "[+] Build SUCCESS! File info:"
ls -lh tkietn_auth.dylib
file tkietn_auth.dylib
