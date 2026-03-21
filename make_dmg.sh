#!/bin/bash

# 1. บิลด์แอปก่อนเพื่อให้แน่ใจว่าเป็นเวอร์ชันล่าสุด
echo "🔨 Building app..."
./build.sh

APP_NAME="DailyLog"
APP_BUNDLE="$APP_NAME.app"
DMG_NAME="$APP_NAME.dmg"
STAGING_DIR="dmg_staging"

# 2. ล้างข้อมูลเก่าถ้ามี
rm -rf "$STAGING_DIR"
rm -f "$DMG_NAME"

# 3. สร้างโฟลเดอร์จัดเตรียม
mkdir -p "$STAGING_DIR"

# 4. คัดลอกแอปไปยังโฟลเดอร์จัดเตรียม
echo "📦 Preparing DMG content..."
cp -R "$APP_BUNDLE" "$STAGING_DIR/"

# 5. สร้าง Shortcut ไปยัง Applications
ln -s /Applications "$STAGING_DIR/Applications"

# 6. สร้างไฟล์ DMG
echo "💿 Creating Disk Image..."
hdiutil create -volname "$APP_NAME Installation" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_NAME"

# 7. ล้างโฟลเดอร์จัดเตรียม
rm -rf "$STAGING_DIR"

echo "✅ Success! File created: $DMG_NAME"
echo "👉 You can now send this .dmg file to your friends."
