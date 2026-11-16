import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: firebaseOptions);
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'الحضور والانصراف',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
        builder: (c, w) =>
            Directionality(textDirection: TextDirection.rtl, child: w!),
        home: StreamBuilder<User?>(
          stream: FirebaseAuth.instance.authStateChanges(),
          builder: (c, s) {
            if (s.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                  body: Center(child: CircularProgressIndicator()));
            }
            return s.data == null ? const LoginPage() : const HomePage();
          },
        ),
      );
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final code = TextEditingController();
  final pass = TextEditingController();
  bool busy = false;
  String? err;

  Future<void> login() async {
    setState(() {
      busy = true;
      err = null;
    });
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: '${code.text.trim().toLowerCase()}@$emailDomain',
        password: pass.text,
      );
    } on FirebaseAuthException {
      err = 'الكود أو الرقم السري غير صحيح';
    } catch (_) {
      err = 'تعذر الاتصال، تأكد من الإنترنت';
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.fingerprint, size: 80, color: Colors.teal),
              const SizedBox(height: 24),
              TextField(
                  controller: code,
                  decoration: const InputDecoration(
                      labelText: 'كود الموظف', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(
                  controller: pass,
                  obscureText: true,
                  decoration: const InputDecoration(
                      labelText: 'الرقم السري', border: OutlineInputBorder())),
              if (err != null)
                Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(err!, style: const TextStyle(color: Colors.red))),
              const SizedBox(height: 20),
              SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                      onPressed: busy ? null : login,
                      child: busy
                          ? const CircularProgressIndicator()
                          : const Text('دخول'))),
            ]),
          ),
        ),
      );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final db = FirebaseFirestore.instance;
  final uid = FirebaseAuth.instance.currentUser!.uid;
  Map<String, dynamic>? emp;
  String deviceId = '';
  String? fatal;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    init();
  }

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      deviceId = prefs.getString('deviceId') ??
          '${DateTime.now().microsecondsSinceEpoch}-$uid';
      await prefs.setString('deviceId', deviceId);

      final ref = db.collection('employees').doc(uid);
      var d = (await ref.get()).data();
      if (d == null) {
        fatal = 'حسابك غير مسجل. راجع المكتب.';
      } else if (d['active'] != true) {
        fatal = 'حسابك موقوف. راجع المكتب.';
      } else if ((d['deviceId'] ?? '') == '') {
        await ref.update({'deviceId': deviceId});
        d['deviceId'] = deviceId;
      } else if (d['deviceId'] != deviceId) {
        fatal = 'حسابك مربوط بموبايل آخر. راجع المكتب لفك الربط.';
      }
      emp = d;
    } catch (_) {
      fatal = 'تعذر تحميل البيانات، تأكد من الإنترنت';
    }
    if (mounted) setState(() {});
  }

  void msg(String t) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(t)));

  Future<void> record(String type) async {
    setState(() => busy = true);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return msg('لازم تسمح بالوصول للموقع');
      }
      if (!await Geolocator.isLocationServiceEnabled()) {
        return msg('شغّل الـ GPS');
      }
      final pos = await Geolocator.getCurrentPosition(
          locationSettings:
              const LocationSettings(accuracy: LocationAccuracy.high));
      if (pos.isMocked) return msg('تم رفض التسجيل: موقع وهمي');

      final allowed = List<String>.from(emp!['sites'] ?? []);
      final sites = (await db.collection('sites').get())
          .docs
          .where((s) => allowed.contains(s.id))
          .toList();
      if (sites.isEmpty) return msg('لم يتم تحديد موقع عمل لك. راجع المكتب.');
      QueryDocumentSnapshot<Map<String, dynamic>>? best;
      double bestDist = double.infinity;
      for (final s in sites) {
        final dist = Geolocator.distanceBetween(
            pos.latitude, pos.longitude, s['lat'] * 1.0, s['lng'] * 1.0);
        if (dist < bestDist) {
          bestDist = dist;
          best = s;
        }
      }
      final radius = (best!['radius'] ?? 100) * 1.0;
      if (bestDist > radius) {
        return msg(
            'أنت خارج نطاق ${best['name']} (يبعد ${bestDist.round()} متر)');
      }

      final auth = LocalAuthentication();
      bool verified = false;
      if (await auth.isDeviceSupported()) {
        verified = await auth.authenticate(
            localizedReason: type == 'in' ? 'تأكيد الحضور' : 'تأكيد الانصراف');
        if (!verified) return msg('فشل التحقق بالبصمة');
      }

      await db.collection('attendance').add({
        'employeeId': uid,
        'employeeName': emp!['name'],
        'deviceId': deviceId,
        'type': type,
        'serverTime': FieldValue.serverTimestamp(),
        'siteId': best.id,
        'siteName': best['name'],
        'lat': pos.latitude,
        'lng': pos.longitude,
        'distance': bestDist.round(),
        'verified': verified,
        'source': 'app',
      });
      msg(type == 'in' ? 'تم تسجيل الحضور ✅' : 'تم تسجيل الانصراف ✅');
    } catch (e) {
      msg('حدث خطأ، حاول مرة أخرى');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (fatal != null) {
      return Scaffold(
          appBar: AppBar(actions: [logoutBtn()]),
          body: Center(
              child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(fatal!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 18)))));
    }
    if (emp == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: Text(emp!['name'] ?? ''), actions: [logoutBtn()]),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: db
            .collection('attendance')
            .where('employeeId', isEqualTo: uid)
            .orderBy('serverTime', descending: true)
            .limit(30)
            .snapshots(),
        builder: (c, s) {
          final docs = s.data?.docs ?? [];
          final lastType = docs.isEmpty ? 'out' : docs.first['type'];
          final isIn = lastType == 'in';
          return Column(children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(children: [
                Text(isIn ? 'أنت الآن: حاضر' : 'أنت الآن: منصرف',
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                SizedBox(
                    width: double.infinity,
                    height: 64,
                    child: FilledButton.icon(
                        onPressed: busy || isIn ? null : () => record('in'),
                        icon: const Icon(Icons.login),
                        label: const Text('تسجيل حضور',
                            style: TextStyle(fontSize: 20)))),
                const SizedBox(height: 12),
                SizedBox(
                    width: double.infinity,
                    height: 64,
                    child: FilledButton.tonalIcon(
                        onPressed: busy || !isIn ? null : () => record('out'),
                        icon: const Icon(Icons.logout),
                        label: const Text('تسجيل انصراف',
                            style: TextStyle(fontSize: 20)))),
                if (busy)
                  const Padding(
                      padding: EdgeInsets.only(top: 16),
                      child: LinearProgressIndicator()),
              ]),
            ),
            const Divider(),
            Expanded(
              child: ListView(
                  children: docs.map((d) {
                final t = (d['serverTime'] as Timestamp?)?.toDate();
                return ListTile(
                  leading: Icon(d['type'] == 'in' ? Icons.login : Icons.logout,
                      color: d['type'] == 'in' ? Colors.green : Colors.orange),
                  title: Text(d['type'] == 'in' ? 'حضور' : 'انصراف'),
                  subtitle: Text(d['siteName'] ?? ''),
                  trailing: Text(t == null
                      ? '...'
                      : DateFormat('yyyy/MM/dd  HH:mm').format(t.toLocal())),
                );
              }).toList()),
            ),
          ]);
        },
      ),
    );
  }

  Widget logoutBtn() => IconButton(
      icon: const Icon(Icons.exit_to_app),
      onPressed: () => FirebaseAuth.instance.signOut());
}
