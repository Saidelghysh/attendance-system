import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart' as intl;
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_config.dart';

const kPrimary = Color(0xFF00796B);
const kDark = Color(0xFF004D40);
const kBg = Color(0xFFF2F5F7);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: firebaseOptions);
  runApp(const App());
}

/// بيانات تسجيل الدخول المؤقتة لعرض تفعيل البصمة بعد أول دخول
List<String>? _pending;

final ButtonStyle bigStyle = FilledButton.styleFrom(
  minimumSize: const Size.fromHeight(54),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
  textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
);

InputDecoration deco(String label, IconData icon, {Widget? suffix}) =>
    InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      suffixIcon: suffix,
      filled: true,
      fillColor: const Color(0xFFF1F4F6),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
    );

String authErr(Object e) {
  if (e is FirebaseAuthException) {
    switch (e.code) {
      case 'network-request-failed':
        return 'تعذر الاتصال، تأكد من الإنترنت';
      case 'too-many-requests':
        return 'محاولات كثيرة، حاول بعد قليل';
      case 'user-disabled':
        return 'الحساب موقوف، راجع المكتب';
      case 'operation-not-allowed':
      case 'invalid-api-key':
        return 'إعدادات التطبيق غير مكتملة، راجع المكتب';
      default:
        return 'الكود أو الرقم السري غير صحيح';
    }
  }
  return 'تعذر تسجيل الدخول، حاول مرة أخرى';
}

Future<void> signIn(String code, String pass) =>
    FirebaseAuth.instance.signInWithEmailAndPassword(
      email: '${code.trim().toLowerCase()}@$emailDomain',
      password: pass,
    );

/// الدخول والقفل بالبصمة
class Bio {
  static const _s = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static final _auth = LocalAuthentication();

  static Future<bool> supported() async {
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  static Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(stickyAuth: true),
      );
    } catch (_) {
      return false;
    }
  }

  static Future<bool> enabled() async {
    try {
      return (await _s.read(key: 'bio')) == '1';
    } catch (_) {
      return false;
    }
  }

  static Future<void> save(String code, String pass) async {
    await _s.write(key: 'bio', value: '1');
    await _s.write(key: 'code', value: code);
    await _s.write(key: 'pass', value: pass);
  }

  static Future<List<String>?> creds() async {
    try {
      if (!await enabled()) return null;
      final c = await _s.read(key: 'code');
      final p = await _s.read(key: 'pass');
      if (c == null || p == null) return null;
      return [c, p];
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear() async {
    try {
      await _s.deleteAll();
    } catch (_) {}
  }
}

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'الحضور والانصراف',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: kPrimary),
      scaffoldBackgroundColor: kBg,
    ),
    builder: (c, w) =>
        Directionality(textDirection: TextDirection.rtl, child: w!),
    home: StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (c, s) {
        if (s.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return s.data == null
            ? const LoginPage()
            : const LockGate(child: HomePage());
      },
    ),
  );
}

/// ---------------- شاشة الدخول ----------------
bool _autoBioTried = false;

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final code = TextEditingController();
  final pass = TextEditingController();
  bool busy = false;
  bool hide = true;
  String? err;
  List<String>? bioCreds;

  @override
  void initState() {
    super.initState();
    loadBio();
  }

  Future<void> loadBio() async {
    final c = await Bio.creds();
    if (!mounted) return;
    setState(() => bioCreds = c);
    if (c != null && !_autoBioTried) {
      _autoBioTried = true;
      bioLogin();
    }
  }

  Future<void> login() async {
    if (code.text.trim().isEmpty || pass.text.isEmpty) {
      setState(() => err = 'اكتب كود الموظف والرقم السري');
      return;
    }
    setState(() {
      busy = true;
      err = null;
    });
    try {
      await signIn(code.text, pass.text);
      _pending = [code.text.trim().toLowerCase(), pass.text];
    } catch (e) {
      err = authErr(e);
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> bioLogin() async {
    final c = bioCreds;
    if (c == null) return;
    if (!await Bio.authenticate('سجّل دخولك بالبصمة')) return;
    setState(() {
      busy = true;
      err = null;
    });
    try {
      await signIn(c[0], c[1]);
    } catch (e) {
      err = authErr(e);
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SingleChildScrollView(
      child: Column(
        children: [
          Container(
            width: double.infinity,
            height: 300,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: [kDark, kPrimary],
              ),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(40)),
            ),
            child: SafeArea(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 92,
                    height: 92,
                    decoration: const BoxDecoration(
                      color: Color(0x33FFFFFF),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.fingerprint,
                      size: 56,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'الحضور والانصراف',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'سجّل دخولك للمتابعة',
                    style: TextStyle(color: Color(0xCCFFFFFF)),
                  ),
                ],
              ),
            ),
          ),
          Transform.translate(
            offset: const Offset(0, -40),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x1A000000),
                    blurRadius: 24,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                children: [
                  TextField(
                    controller: code,
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    decoration: deco('كود الموظف', Icons.badge_outlined),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: pass,
                    obscureText: hide,
                    onSubmitted: (_) => login(),
                    decoration: deco(
                      'الرقم السري',
                      Icons.lock_outline,
                      suffix: IconButton(
                        icon: Icon(
                          hide
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                        onPressed: () => setState(() => hide = !hide),
                      ),
                    ),
                  ),
                  if (err != null)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(top: 14),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFEBEE),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        err!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Color(0xFFB71C1C)),
                      ),
                    ),
                  const SizedBox(height: 20),
                  FilledButton(
                    style: bigStyle,
                    onPressed: busy ? null : login,
                    child: busy
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : const Text('دخول'),
                  ),
                  if (bioCreds != null) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(54),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: busy ? null : bioLogin,
                      icon: const Icon(Icons.fingerprint),
                      label: const Text('الدخول بالبصمة'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// ---------------- قفل التطبيق بالبصمة ----------------
class LockGate extends StatefulWidget {
  final Widget child;
  const LockGate({super.key, required this.child});
  @override
  State<LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<LockGate> with WidgetsBindingObserver {
  bool locked = false;
  bool ready = false;
  DateTime? pausedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> init() async {
    final on = await Bio.enabled();
    if (!mounted) return;
    setState(() {
      locked = on;
      ready = true;
    });
    if (on) unlock();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    onState(state);
  }

  Future<void> onState(AppLifecycleState state) async {
    if (state == AppLifecycleState.paused) pausedAt = DateTime.now();
    if (state == AppLifecycleState.resumed && pausedAt != null) {
      final away = DateTime.now().difference(pausedAt!);
      pausedAt = null;
      if (away.inSeconds > 60 && await Bio.enabled() && mounted) {
        setState(() => locked = true);
        unlock();
      }
    }
  }

  Future<void> unlock() async {
    final ok = await Bio.authenticate('افتح التطبيق بالبصمة');
    if (ok && mounted) setState(() => locked = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Stack(
      children: [
        widget.child,
        if (locked)
          Positioned.fill(
            child: Material(
              color: kDark,
              child: SafeArea(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.lock_outline,
                        size: 72,
                        color: Colors.white,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'التطبيق مقفل',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 28),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: kDark,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 28,
                            vertical: 16,
                          ),
                        ),
                        onPressed: unlock,
                        icon: const Icon(Icons.fingerprint),
                        label: const Text('فتح بالبصمة'),
                      ),
                      TextButton(
                        onPressed: () => FirebaseAuth.instance.signOut(),
                        child: const Text(
                          'تسجيل خروج',
                          style: TextStyle(color: Color(0xCCFFFFFF)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// ---------------- ساعة حيّة ----------------
class LiveClock extends StatefulWidget {
  const LiveClock({super.key});
  @override
  State<LiveClock> createState() => _LiveClockState();
}

class _LiveClockState extends State<LiveClock> {
  Timer? t;
  DateTime now = DateTime.now();

  @override
  void initState() {
    super.initState();
    t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => now = DateTime.now());
    });
  }

  @override
  void dispose() {
    t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text(
    intl.DateFormat('HH:mm:ss').format(now),
    textDirection: TextDirection.ltr,
    style: const TextStyle(
      color: Colors.white,
      fontSize: 44,
      fontWeight: FontWeight.w300,
      letterSpacing: 2,
    ),
  );
}

const _days = [
  'الاثنين',
  'الثلاثاء',
  'الأربعاء',
  'الخميس',
  'الجمعة',
  'السبت',
  'الأحد',
];
String dayLabel(DateTime d) =>
    '${_days[d.weekday - 1]}  ${intl.DateFormat('yyyy/MM/dd').format(d)}';
String hm(DateTime? d) =>
    d == null ? '--:--' : intl.DateFormat('HH:mm').format(d.toLocal());
String dur(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  return '${h}س ${m}د';
}

/// ---------------- الشاشة الرئيسية ----------------
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
      deviceId =
          prefs.getString('deviceId') ??
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
    if (fatal == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => offerBio());
    }
  }

  void msg(String t) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  Future<void> offerBio() async {
    final p = _pending;
    _pending = null;
    if (p == null || !mounted) return;
    if (!await Bio.supported() || await Bio.enabled()) return;
    if (!mounted) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('الدخول بالبصمة'),
        content: const Text(
          'تحب تفعّل الدخول بالبصمة بدل كتابة الرقم السري كل مرة؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('لاحقًا'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('تفعيل'),
          ),
        ],
      ),
    );
    if (yes == true) await enableBio(p[0], p[1]);
  }

  Future<void> enableBio(String code, String pass) async {
    if (!await Bio.supported()) {
      msg('الجهاز لا يدعم البصمة');
      return;
    }
    if (!await Bio.authenticate('تأكيد تفعيل الدخول بالبصمة')) {
      msg('لم يتم التفعيل');
      return;
    }
    await Bio.save(code, pass);
    msg('تم تفعيل الدخول بالبصمة ✅');
  }

  Future<void> askPassAndEnable() async {
    final c = TextEditingController();
    final pw = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الرقم السري'),
        content: TextField(
          controller: c,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'الرقم السري'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text),
            child: const Text('متابعة'),
          ),
        ],
      ),
    );
    if (pw == null || pw.isEmpty) return;
    final user = FirebaseAuth.instance.currentUser!;
    try {
      await user.reauthenticateWithCredential(
        EmailAuthProvider.credential(email: user.email!, password: pw),
      );
    } on FirebaseAuthException {
      msg('الرقم السري غير صحيح');
      return;
    }
    await enableBio('${emp?['code'] ?? ''}', pw);
  }

  void settings() {
    showModalBottomSheet(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FutureBuilder<bool>(
                future: Bio.enabled(),
                builder: (c, s) => SwitchListTile(
                  secondary: const Icon(Icons.fingerprint),
                  title: const Text('الدخول بالبصمة'),
                  subtitle: const Text('فتح التطبيق وتسجيل الدخول بالبصمة'),
                  value: s.data ?? false,
                  onChanged: (v) async {
                    if (v) {
                      Navigator.pop(c);
                      await askPassAndEnable();
                    } else {
                      await Bio.clear();
                      set(() {});
                      msg('تم إيقاف الدخول بالبصمة');
                    }
                  },
                ),
              ),
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('تسجيل خروج'),
                onTap: () {
                  Navigator.pop(c);
                  FirebaseAuth.instance.signOut();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

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
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      if (pos.isMocked) return msg('تم رفض التسجيل: موقع وهمي');

      final auth = LocalAuthentication();
      bool verified = false;
      if (await auth.isDeviceSupported()) {
        verified = await auth.authenticate(
          localizedReason: type == 'in' ? 'تأكيد الحضور' : 'تأكيد الانصراف',
        );
        if (!verified) return msg('فشل التحقق بالبصمة');
      }

      // تحديد المكان تلقائيًا: أقرب موقع معروف، وإلا يتسجل موقع جديد
      final siteSnap = await db.collection('sites').get();
      QueryDocumentSnapshot<Map<String, dynamic>>? best;
      double bestDist = double.infinity;
      for (final s in siteSnap.docs) {
        final sd = s.data();
        if (sd['lat'] == null || sd['lng'] == null) continue;
        final dist = Geolocator.distanceBetween(
          pos.latitude,
          pos.longitude,
          sd['lat'] * 1.0,
          sd['lng'] * 1.0,
        );
        if (dist < bestDist) {
          bestDist = dist;
          best = s;
        }
      }
      String siteId;
      String siteName;
      if (best != null && bestDist <= ((best.data()['radius'] ?? 150) * 1.0)) {
        siteId = best.id;
        siteName = '${best.data()['name'] ?? ''}';
      } else {
        siteName = 'موقع جديد ${siteSnap.docs.length + 1}';
        final ref = await db.collection('sites').add({
          'name': siteName,
          'lat': pos.latitude,
          'lng': pos.longitude,
          'radius': 150,
          'auto': true,
          'createdBy': uid,
        });
        siteId = ref.id;
        bestDist = 0;
      }

      await db.collection('attendance').add({
        'employeeId': uid,
        'employeeName': emp!['name'],
        'deviceId': deviceId,
        'type': type,
        'serverTime': FieldValue.serverTimestamp(),
        'siteId': siteId,
        'siteName': siteName,
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

  Widget header({required bool isIn, String? since, String? site}) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [kDark, kPrimary],
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 26),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'مرحبًا',
                        style: TextStyle(color: Color(0xCCFFFFFF)),
                      ),
                      Text(
                        '${emp!['name'] ?? ''}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: settings,
                  icon: const Icon(
                    Icons.settings_outlined,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const LiveClock(),
            const SizedBox(height: 4),
            Text(
              dayLabel(DateTime.now()),
              style: const TextStyle(color: Color(0xCCFFFFFF)),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0x26FFFFFF),
                borderRadius: BorderRadius.circular(30),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.circle,
                    size: 12,
                    color: isIn ? const Color(0xFF69F0AE) : Colors.orangeAccent,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isIn
                        ? 'حاضر منذ $since${(site ?? '').isEmpty ? '' : ' • $site'}'
                        : 'لم تسجّل حضور بعد',
                    style: const TextStyle(color: Colors.white),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget actionButton(bool isIn) {
    final color = isIn ? const Color(0xFFE65100) : const Color(0xFF2E7D32);
    return Material(
      color: color,
      shape: const CircleBorder(),
      elevation: 10,
      shadowColor: color,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: busy ? null : () => record(isIn ? 'out' : 'in'),
        child: SizedBox(
          width: 190,
          height: 190,
          child: Center(
            child: busy
                ? const CircularProgressIndicator(color: Colors.white)
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isIn ? Icons.logout : Icons.fingerprint,
                        size: 66,
                        color: Colors.white,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        isIn ? 'تسجيل انصراف' : 'تسجيل حضور',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget stat(IconData icon, String label, String value) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F000000),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: kPrimary, size: 22),
          const SizedBox(height: 6),
          Text(
            value,
            textDirection: TextDirection.ltr,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (fatal != null) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.info_outline, size: 64, color: kPrimary),
                  const SizedBox(height: 16),
                  Text(
                    fatal!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 18),
                  ),
                  const SizedBox(height: 24),
                  OutlinedButton(
                    onPressed: () => FirebaseAuth.instance.signOut(),
                    child: const Text('تسجيل خروج'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    if (emp == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: db
            .collection('attendance')
            .where('employeeId', isEqualTo: uid)
            .snapshots(),
        builder: (c, s) {
          final docs = [...(s.data?.docs ?? [])];
          DateTime tOf(QueryDocumentSnapshot<Map<String, dynamic>> d) =>
              (d['serverTime'] as Timestamp?)?.toDate().toLocal() ??
              DateTime.now();
          docs.sort((a, b) => tOf(b).compareTo(tOf(a)));
          if (docs.length > 60) docs.removeRange(60, docs.length);

          final isIn = docs.isNotEmpty && docs.first['type'] == 'in';
          final lastSite = docs.isEmpty
              ? ''
              : '${docs.first['siteName'] ?? ''}';

          // ملخص اليوم
          final now = DateTime.now();
          final start = DateTime(now.year, now.month, now.day);
          final today = docs.where((d) => tOf(d).isAfter(start)).toList()
            ..sort((a, b) => tOf(a).compareTo(tOf(b)));
          DateTime? firstIn;
          DateTime? lastOut;
          DateTime? openIn;
          var worked = Duration.zero;
          for (final d in today) {
            final t = tOf(d);
            if (d['type'] == 'in') {
              firstIn ??= t;
              openIn ??= t;
            } else {
              lastOut = t;
              if (openIn != null) {
                worked += t.difference(openIn);
                openIn = null;
              }
            }
          }
          if (openIn != null) worked += now.difference(openIn);

          // السجل مجمّع بالأيام
          final items = <Widget>[];
          String? lastDay;
          for (final d in docs) {
            final t = tOf(d);
            final dayKey = intl.DateFormat('yyyy-MM-dd').format(t);
            if (dayKey != lastDay) {
              lastDay = dayKey;
              items.add(
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
                  child: Text(
                    dayLabel(t),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.black54,
                    ),
                  ),
                ),
              );
            }
            final inn = d['type'] == 'in';
            items.add(
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: inn
                        ? const Color(0xFFE8F5E9)
                        : const Color(0xFFFFF3E0),
                    child: Icon(
                      inn ? Icons.login : Icons.logout,
                      color: inn
                          ? const Color(0xFF2E7D32)
                          : const Color(0xFFE65100),
                    ),
                  ),
                  title: Text(
                    inn ? 'حضور' : 'انصراف',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text('${d['siteName'] ?? ''}'),
                  trailing: Text(
                    hm(t),
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            );
          }

          return Column(
            children: [
              header(
                isIn: isIn,
                since: isIn ? hm(tOf(docs.first)) : null,
                site: lastSite,
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 22, 16, 24),
                  children: [
                    Center(child: actionButton(isIn)),
                    const SizedBox(height: 22),
                    Row(
                      children: [
                        stat(Icons.login, 'أول حضور', hm(firstIn)),
                        const SizedBox(width: 10),
                        stat(Icons.logout, 'آخر انصراف', hm(lastOut)),
                        const SizedBox(width: 10),
                        stat(Icons.timer_outlined, 'ساعات اليوم', dur(worked)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'السجل',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (items.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: Text('لا توجد سجلات بعد')),
                      ),
                    ...items,
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
