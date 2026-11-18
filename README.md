# نظام حضور وانصراف العمال

- `docs/` — لوحة المكتب (تُنشر على GitHub Pages)
- `worker_app/` — تطبيق العمال (Flutter / أندرويد)
- `firestore.rules` — قواعد الأمان

## التشغيل (مرة واحدة)

1. **Firebase**: فعّل Authentication (Email/Password) و Firestore.
2. **القواعد**: Firestore ← Rules ← الصق محتوى `firestore.rules` ← Publish.
3. **الإعدادات**: عدّل `docs/firebase-config.json` بقيم مشروعك (بيستخدمها التطبيق واللوحة).
4. **اللوحة**: GitHub ← Settings ← Pages ← Branch `main` ← Folder `/docs`.
5. افتح رابط اللوحة ← "أول مرة؟ إنشاء حساب المدير" (مرة واحدة فورًا بعد نشر القواعد).
6. أضف المواقع ثم العمال من اللوحة.
7. **التطبيق**: Actions ← Build worker APK ← Run workflow ← حمّل `worker-app-apk`.

الدخول للعامل: كود الموظف + الرقم السري اللي سجلته من اللوحة.
