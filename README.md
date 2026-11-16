# نظام حضور وانصراف العمال

- `worker_app/` — تطبيق Flutter للعمال والموظفين (أندرويد)
- `admin_panel/` — لوحة المكتب (صفحة ويب تُنشر على GitHub Pages)
- `firestore.rules` / `firestore.indexes.json` — قواعد الأمان والفهارس

## خطوات التشغيل

### 1) Firebase
1. أنشئ مشروع في https://console.firebase.google.com
2. **Authentication** → فعّل Email/Password
3. **Firestore Database** → Create (Production mode)
4. **Project settings** → أضف تطبيق **Web** وانسخ الإعدادات إلى `admin_panel/firebase-config.js`
5. أضف تطبيق **Android** بالاسم `com.company.attendance_worker` وانسخ القيم (apiKey, appId, messagingSenderId, projectId) إلى `worker_app/lib/firebase_config.dart`
6. انشر القواعد والفهارس:
   ```
   npm i -g firebase-tools
   firebase login
   firebase use --add
   firebase deploy --only firestore
   ```

### 2) أول مدير (مرة واحدة يدويًا)
1. Authentication → Add user (إيميلك + رقم سري) وانسخ الـ UID
2. Firestore → Start collection `admins` → Document ID = الـ UID → حقل `role` (string) = `admin`
3. لموظفي المكتب (عرض فقط): نفس الخطوات لكن `role` = `office`

### 3) لوحة المكتب
Settings → Pages → Branch: main, Folder: `/admin_panel` (أو انسخ المجلد لمستودع Pages). افتح الرابط وسجل دخول.
ثم: أضف المواقع، ثم أضف العمال.

### 4) تطبيق العمال
- محليًا: `cd worker_app && ./setup.sh && flutter pub get && flutter run`
- أو من GitHub: تبويب Actions → **Build worker APK** → Run workflow → حمّل `worker-app-apk`

### دخول العامل
كود الموظف + الرقم السري اللي سجلته له من اللوحة.

## الحماية
- وقت التسجيل من السيرفر (مفروض في القواعد)
- ربط كل حساب بجهاز واحد (فك الربط من اللوحة)
- نطاق الموقع + رفض الموقع الوهمي + بصمة الموبايل
- ملاحظة: فحص النطاق يتم داخل التطبيق، والمسافة تتسجل في كل سجل للمراجعة
