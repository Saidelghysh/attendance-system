#!/usr/bin/env bash
# يشغَّل مرة واحدة داخل worker_app: يولّد مجلد android ويضيف الصلاحيات
set -e

# توليد lib/firebase_config.dart من ../docs/firebase-config.json (لو اتملى)
CFG=../docs/firebase-config.json
if [ -f "$CFG" ] && ! grep -q 'PUT_' "$CFG"; then
  python3 gen_config.py
fi
if [ ! -f lib/firebase_config.dart ]; then
  echo "ERROR: عدّل docs/firebase-config.json أولًا"; exit 1
fi
flutter create --org com.company --project-name attendance_worker --platforms=android .
rm -rf test

MANIFEST=android/app/src/main/AndroidManifest.xml
if ! grep -q ACCESS_FINE_LOCATION "$MANIFEST"; then
  sed -i 's#<application#<uses-permission android:name="android.permission.INTERNET"/>\n    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>\n    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>\n    <uses-permission android:name="android.permission.USE_BIOMETRIC"/>\n    <application#' "$MANIFEST"
fi

# local_auth يحتاج FlutterFragmentActivity
KT=$(find android/app/src/main -name MainActivity.kt | head -n1)
cat > "$KT" <<'KOTLIN'
package com.company.attendance_worker

import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app/updater")
            .setMethodCallHandler { call, result ->
                if (call.method == "open") {
                    val url = call.argument<String>("url")
                    try {
                        val i = Intent(Intent.ACTION_VIEW, Uri.parse(url))
                        i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(i)
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                } else {
                    result.notImplemented()
                }
            }
    }
}
KOTLIN

# الحد الأدنى للإصدار (Firebase)
for f in android/app/build.gradle android/app/build.gradle.kts; do
  [ -f "$f" ] && sed -i 's/minSdk = flutter.minSdkVersion/minSdk = 23/; s/minSdkVersion flutter.minSdkVersion/minSdkVersion 23/' "$f"
done

# اسم التطبيق تحت الأيقونة على الموبايل (من app_name.txt)
NAME="الحضور والانصراف"
if [ -f app_name.txt ]; then NAME=$(head -n1 app_name.txt | tr -d '\r'); fi
sed -i "s#android:label=\"[^\"]*\"#android:label=\"$NAME\"#" "$MANIFEST"

# أيقونة التطبيق = لوجو الشركة (لو assets/logo.png موجود)
if [ -f assets/logo.png ]; then
  flutter pub get
  dart run flutter_launcher_icons
fi
# اسم التطبيق على الموبايل (افتراضي: الحضور، أو اكتب اسم الشركة في ملف app_name.txt)
APP_NAME="الحضور"
if [ -f app_name.txt ]; then APP_NAME="$(tr -d '\r\n' < app_name.txt)"; fi
sed -i "s#android:label=\"[^\"]*\"#android:label=\"$APP_NAME\"#" "$MANIFEST"

# أيقونة التطبيق: لو اترفع assets/logo.png بيتحول لأيقونة الموبايل
if [ -f assets/logo.png ]; then
  cat > flutter_launcher_icons.yaml <<YAML
flutter_launcher_icons:
  android: true
  ios: false
  image_path: "assets/logo.png"
YAML
  flutter pub add --dev flutter_launcher_icons
  flutter pub get
  dart run flutter_launcher_icons
fi
echo "تم. الآن: flutter pub get && flutter run"
