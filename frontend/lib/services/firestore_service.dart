import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FirestoreService {
  final _db = FirebaseFirestore.instance;

  Future<void> saveUserData(User user) async {
    final userRef = _db.collection('users').doc(user.uid);

    await userRef.set({
      'name': user.displayName,
      'email': user.email,
      'onboarded': true,
      'lastLogin': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
