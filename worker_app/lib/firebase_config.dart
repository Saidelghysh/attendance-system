import 'package:firebase_core/firebase_core.dart';

// عدّل القيم دي من: Firebase Console > Project settings > Your apps > Android
const firebaseOptions = FirebaseOptions(
  apiKey: 'PUT_API_KEY',
  appId: 'PUT_APP_ID',
  messagingSenderId: 'PUT_SENDER_ID',
  projectId: 'PUT_PROJECT_ID',
);

// الإيميل الداخلي للدخول: كود الموظف + الدومين ده (لازم يطابق لوحة المكتب)
const emailDomain = 'attend.app';
