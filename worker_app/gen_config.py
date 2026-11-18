import json
c=json.load(open('../docs/firebase-config.json'))
open('lib/firebase_config.dart','w').write(f"""import 'package:firebase_core/firebase_core.dart';

const firebaseOptions = FirebaseOptions(
  apiKey: '{c["apiKey"]}',
  appId: '{c["androidAppId"]}',
  messagingSenderId: '{c["messagingSenderId"]}',
  projectId: '{c["projectId"]}',
);

const emailDomain = '{c.get("emailDomain","attend.app")}';
""")
print("generated firebase_config.dart")
