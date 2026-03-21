# DailyLog - macOS Menu Bar Productivity Tracker

DailyLog เป็นแอปพลิเคชันบนแถบเมนู (Menu Bar) ของ macOS ที่ออกแบบมาเพื่อช่วยให้คุณติดตามประสิทธิภาพการทำงานผ่านการตรวจสอบการใช้งานแอปโดยอัตโนมัติ พร้อมทั้งมีระบบ Gamification และการมอนิเตอร์ระบบเครื่อง

## ฟีเจอร์หลัก
- **การติดตามการใช้งานแอป (App Usage Tracking):** ตรวจสอบแอปที่ใช้งานอยู่ (Frontmost Application) โดยอัตโนมัติและบันทึกเวลาที่ใช้ ข้อมูลจะถูกรีเซ็ตทุกวัน
- **การมอนิเตอร์ระบบ (System Monitoring):** แสดงสถานะ CPU, RAM, GPU, พื้นที่ดิสก์, อุณหภูมิเครื่อง และความเร็วเครือข่ายได้แบบเรียลไทม์บนแถบเมนู
- **ระบบ Gamification:**
    - **เลเวลและ EXP:** รับ 1 EXP สำหรับทุกๆ 1 นาทีที่ใช้ในแอปใดก็ได้ เพื่ออัปเลเวลและติดตามความก้าวหน้าในการทำงานตลอดอายุการใช้งาน
- **การรวมเข้ากับแถบเมนู (Menu Bar Integration):** ทำงานทั้งหมดจากแถบเมนู macOS เพื่อประสบการณ์ที่ไม่รบกวนการทำงาน

## เทคโนโลยีที่ใช้
- **ภาษา:** Swift 5.10
- **เฟรมเวิร์ก:**
    - **SwiftUI:** สำหรับส่วนติดต่อผู้ใช้ทั้งหมด
    - **AppKit:** สำหรับการเชื่อมต่อแถบเมนู (`NSMenuBarExtra`), การติดตามแอป (`NSWorkspace`), และการจัดการ Lifecycle
    - **Combine:** สำหรับการจัดการสถานะแบบ Reactive ภายใน ViewModels
- **การบันทึกข้อมูล:** `UserDefaults` พร้อม `JSONEncoder`/`JSONDecoder`

## โครงสร้างโปรเจกต์
- `Sources/DailyLog/`
    - `DailyLogApp.swift`: จุดเริ่มต้นของแอปและการกำหนดค่า Menu Bar
    - `Managers/`: การจัดการระบบ (`SystemMonitorManager`)
    - `Models/`: โครงสร้างข้อมูล (`GameModels`)
    - `ViewModels/`: ตรรกะทางธุรกิจและการจัดการสถานะ (`TrackingViewModel`)
    - `Views/`: SwiftUI Views สำหรับอินเทอร์เฟซ (`MenuBarView`, `HistoryView`, `SettingsView`)
- `Package.swift`: การกำหนดค่า Swift Package Manager
- `build.sh`: สคริปต์สำหรับสร้างและแพ็คเกจแอป (.app bundle)
- `make_dmg.sh`: สคริปต์สำหรับสร้างไฟล์ติดตั้ง .dmg

## การติดตั้งและรัน

### การสร้าง (Build) จากเทอร์มินัล
หากต้องการสร้างโปรเจกต์โดยใช้ Swift Package Manager:
```bash
swift build -c release
```

### การสร้างเป็น .app Bundle
รันสคริปต์การสร้างที่เตรียมไว้เพื่อสร้างแอปพลิเคชัน macOS:
```bash
./build.sh
```
สิ่งนี้จะสร้าง `DailyLog.app` ในโฟลเดอร์ root

### การรันเทส (Running Tests)
หากต้องการรันชุดการทดสอบอัตโนมัติ:
```bash
swift test
```

## ข้อตกลงในการพัฒนา
- **สถาปัตยกรรม MVVM:** ควรแยกตรรกะไว้ใน ViewModels ขณะที่ Views ควรเป็นแบบ Declarative
- **การจัดการสถานะ:** ใช้ `@StateObject` และ `@Published` สำหรับการอัปเดต UI แบบ Reactive
- **ตรรกะการติดตาม:** `TrackingViewModel` ใช้ตัวจับเวลา 1 วินาทีเพื่อตรวจสอบแอปที่ใช้งานอยู่
- **การนำทางและยืนยัน (สำคัญ):**
    - **ห้ามใช้ Popups พื้นฐาน:** ห้ามใช้ `.sheet()`, `.fullScreenCover()`, หรือ `.alert()` ของระบบ เนื่องจากอาจทำให้หน้าต่างหลักปิดลงได้ใน `MenuBarExtra`
    - **วิธีแก้:** ใช้การสลับ View ภายใน `VStack` หลัก หรือใช้ `ZStack` พร้อม Custom Overlay สำหรับการยืนยันข้อมูล
