#!/bin/bash

# 1. เข้าไปยังโฟลเดอร์ DailyLog
# cd "$(dirname "$0")"

echo "🚀 Building DailyLog..."

# 2. บิลด์โปรเจกต์แบบ Release
swift build -c release

# 3. สร้างโครงสร้าง .app
APP_NAME="DailyLog.app"
mkdir -p "$APP_NAME/Contents/MacOS"

# 4. คัดลอกไฟล์ Binary และ Info.plist
cp .build/release/DailyLog "$APP_NAME/Contents/MacOS/"
cp Info.plist "$APP_NAME/Contents/"

echo "✅ Build Complete: $APP_NAME"

# 5. เปิดแอปทันที
open "$APP_NAME"