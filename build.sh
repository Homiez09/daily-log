#!/bin/bash

# 1. เข้าไปยังโฟลเดอร์ DailyLog
# cd "$(dirname "$0")"

echo "🚀 Building DailyLog..."

# 2. บิลด์โปรเจกต์แบบ Release
swift build -c release

# 3. สร้างโครงสร้าง .app (binary หลัก + fan helper + Info.plist + ไอคอน)
APP_NAME="DailyLog.app"
./scripts/bundle.sh "$APP_NAME"

echo "✅ Build Complete: $APP_NAME"

# 5. เปิดแอปทันที
open "$APP_NAME"