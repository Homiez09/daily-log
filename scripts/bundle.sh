#!/bin/bash
set -e

# ประกอบ DailyLog.app จาก binary ที่ build แบบ release แล้ว (ใช้ร่วมกันโดย build.sh และ release.sh)
# ใช้งาน: scripts/bundle.sh [ชื่อ .app]   (ค่าเริ่มต้น: DailyLog.app)

cd "$(dirname "$0")/.."
APP_BUNDLE="${1:-DailyLog.app}"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"

cp .build/release/DailyLog "$APP_BUNDLE/Contents/MacOS/"
# helper ที่รันด้วยสิทธิ์ root เฉพาะตอนผู้ใช้สั่งปรับความเร็วพัดลม (ต้องอยู่ข้าง binary หลัก)
cp .build/release/DailyLogFanHelper "$APP_BUNDLE/Contents/MacOS/"
cp Info.plist "$APP_BUNDLE/Contents/"
cp Resources/AppIcon.icns "$APP_BUNDLE/Contents/Resources/"
