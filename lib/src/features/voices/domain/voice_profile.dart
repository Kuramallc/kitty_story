import 'package:cloud_firestore/cloud_firestore.dart';

/// Lifecycle of a voice profile. The client writes `pending` at creation;
/// the `createVoiceProfile` Cloud Function moves it through
/// `processing` → `ready` (or `failed`).
enum VoiceStatus {
  pending,
  processing,
  ready,
  failed;

  static VoiceStatus parse(String? raw) => VoiceStatus.values.firstWhere(
        (s) => s.name == raw,
        orElse: () => VoiceStatus.pending,
      );
}

/// A cloned caregiver voice ("Mom", "Dad", "Grandma"…).
class VoiceProfile {
  const VoiceProfile({
    required this.id,
    required this.name,
    required this.status,
    this.elevenLabsVoiceId,
    this.error,
    this.createdAt,
  });

  final String id;
  final String name;
  final VoiceStatus status;
  final String? elevenLabsVoiceId;
  final String? error;
  final DateTime? createdAt;

  bool get isReady => status == VoiceStatus.ready;

  factory VoiceProfile.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    return VoiceProfile(
      id: doc.id,
      name: (data['name'] as String?) ?? 'Voice',
      status: VoiceStatus.parse(data['status'] as String?),
      elevenLabsVoiceId: data['elevenLabsVoiceId'] as String?,
      error: data['error'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}
