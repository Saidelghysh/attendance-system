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
cat > "$KT" <<KOTLIN
package com.company.attendance_worker

import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity()
KOTLIN

# الحد الأدنى للإصدار (Firebase)
for f in android/app/build.gradle android/app/build.gradle.kts; do
  [ -f "$f" ] && sed -i 's/minSdk = flutter.minSdkVersion/minSdk = 23/; s/minSdkVersion flutter.minSdkVersion/minSdkVersion 23/' "$f"
done
echo "تم. الآن: flutter pub get && flutter run"
