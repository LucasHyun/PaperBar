#!/bin/bash
# PaperBar.app 빌드 스크립트
#   ./build.sh                 → build/PaperBar.app (지금 맥의 아키텍처)
#   ./build.sh --universal     → Apple Silicon + Intel 겸용 (Xcode 필요)
#   ./build.sh --install       → 빌드 후 /Applications 에 설치하고 실행
#   VERSION=1.2.0 ./build.sh   → Info.plist 버전 지정 (릴리스 워크플로가 사용)
set -euo pipefail
cd "$(dirname "$0")"

UNIVERSAL=0
INSTALL=0
for arg in "$@"; do
    case "$arg" in
        --universal) UNIVERSAL=1 ;;
        --install) INSTALL=1 ;;
        *) echo "알 수 없는 옵션: $arg"; exit 1 ;;
    esac
done

FLAGS=(-c release)
if [[ $UNIVERSAL == 1 ]]; then
    FLAGS+=(--arch arm64 --arch x86_64)
fi

echo "▶ 릴리스 빌드 중…"
swift build "${FLAGS[@]}"
BIN="$(swift build "${FLAGS[@]}" --show-bin-path)/PaperBar"

APP="build/PaperBar.app"
echo "▶ 앱 번들 만드는 중…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/PaperBar"
cp Resources/Info.plist "$APP/Contents/Info.plist"

if [[ -n "${VERSION:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
fi

# 로컬 실행용 ad-hoc 서명 (Apple 공증은 아님)
codesign --force --deep --sign - "$APP"
echo "✔ $APP 완성"

if [[ $INSTALL == 1 ]]; then
    pkill -x PaperBar 2>/dev/null || true
    rm -rf /Applications/PaperBar.app
    cp -R "$APP" /Applications/
    open /Applications/PaperBar.app
    echo "✔ /Applications/PaperBar.app 설치 후 실행했어요 (메뉴바 오른쪽을 확인하세요)"
fi
