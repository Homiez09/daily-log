#!/bin/bash
set -e

# ใช้งาน: ./release.sh <version>  เช่น ./release.sh 1.1.0
# ทำ: อัปเดตเวอร์ชันใน Info.plist -> build release -> pack .app -> zip
#     -> commit + tag -> push -> สร้าง GitHub Release พร้อมแนบไฟล์ zip

if [ -z "$1" ]; then
    echo "❌ กรุณาระบุ version เช่น: ./release.sh 1.1.0"
    exit 1
fi

VERSION="$1"
TAG="v$VERSION"
APP_NAME="DailyLog"
APP_BUNDLE="$APP_NAME.app"
ZIP_NAME="$APP_NAME-$TAG.zip"
PLISTBUDDY="/usr/libexec/PlistBuddy"

cd "$(dirname "$0")"

# 0. ต้องอยู่บน main และ working tree ต้องสะอาด (ยกเว้น Info.plist ที่กำลังจะแก้)
BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$BRANCH" != "main" ]; then
    echo "❌ ต้อง release จาก branch main เท่านั้น (ตอนนี้อยู่ที่: $BRANCH)"
    exit 1
fi

if [ -n "$(git status --porcelain | grep -v ' Info.plist$')" ]; then
    echo "❌ มีการเปลี่ยนแปลงที่ยังไม่ commit อยู่ กรุณา commit หรือ stash ก่อน"
    git status --short
    exit 1
fi

if git rev-parse "$TAG" >/dev/null 2>&1; then
    echo "❌ tag $TAG มีอยู่แล้ว"
    exit 1
fi

# 1. อัปเดตเวอร์ชันใน Info.plist
echo "📝 Updating Info.plist to version $VERSION..."
$PLISTBUDDY -c "Set :CFBundleShortVersionString $VERSION" Info.plist
if $PLISTBUDDY -c "Print :CFBundleVersion" Info.plist >/dev/null 2>&1; then
    $PLISTBUDDY -c "Set :CFBundleVersion $VERSION" Info.plist
else
    $PLISTBUDDY -c "Add :CFBundleVersion string $VERSION" Info.plist
fi

# 2. บิลด์โปรเจกต์แบบ Release
echo "🚀 Building DailyLog $VERSION (release)..."
swift build -c release

# 3. สร้างโครงสร้าง .app
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
cp .build/release/DailyLog "$APP_BUNDLE/Contents/MacOS/"
cp Info.plist "$APP_BUNDLE/Contents/"

# 4. เซ็นแบบ ad-hoc เพื่อลดปัญหา Gatekeeper (ยังไม่ notarize เพราะไม่มี Developer ID)
echo "🔏 Ad-hoc code signing..."
codesign --force --deep --sign - "$APP_BUNDLE"

# 5. zip สำหรับแจกจ่าย (ใช้ ditto เพื่อรักษา resource fork / metadata ของ .app)
echo "📦 Zipping $ZIP_NAME..."
rm -f "$ZIP_NAME"
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_NAME"

# 6. commit เวอร์ชันใหม่ + tag
echo "🏷️  Committing and tagging $TAG..."
git add Info.plist
git commit -m "chore: release $TAG"
git tag -a "$TAG" -m "Release $TAG"

# 7. push commit + tag ขึ้น origin
echo "⬆️  Pushing to origin..."
git push origin main
git push origin "$TAG"

# 8. สร้าง GitHub Release พร้อมแนบไฟล์ zip
echo "🐙 Creating GitHub Release $TAG..."
gh release create "$TAG" "$ZIP_NAME" \
    --title "$APP_NAME $TAG" \
    --generate-notes

echo "✅ Release $TAG เสร็จสมบูรณ์: $ZIP_NAME"
