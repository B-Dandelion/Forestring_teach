import 'package:supabase_flutter/supabase_flutter.dart';

class AuthFailure implements Exception {
  const AuthFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

class AuthRepository {
  AuthRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Session? get currentSession => _client.auth.currentSession;

  User? get currentUser => _client.auth.currentUser;

  Future<Session> signInWithNameAndPin({
    required String name,
    required String pin,
  }) async {
    final normalizedName = name.trim();

    if (normalizedName.isEmpty) {
      throw const AuthFailure('이름을 입력해주세요.');
    }

    if (!RegExp(r'^\d{4}$').hasMatch(pin)) {
      throw const AuthFailure('PIN은 4자리 숫자로 입력해주세요.');
    }

    dynamic response;

    try {
      response = await _client.functions.invoke(
        'login-with-pin',
        body: {
          'name': normalizedName,
          'pin': pin,
        },
      );
    } catch (_) {
      throw const AuthFailure(
        '로그인 서버에 연결하지 못했습니다.',
      );
    }

    final data = response.data;

    if (data is! Map) {
      throw const AuthFailure(
        '로그인 서버 응답 형식이 올바르지 않습니다.',
      );
    }

    final tokenHash = data['tokenHash'];

    if (tokenHash is! String || tokenHash.isEmpty) {
      final message = data['message'];

      throw AuthFailure(
        message is String ? message : '이름 또는 PIN이 올바르지 않습니다.',
      );
    }

    AuthResponse authResponse;

    try {
      authResponse = await _client.auth.verifyOTP(
        type: OtpType.email,
        tokenHash: tokenHash,
      );
    } on AuthException catch (error) {
      throw AuthFailure(
        '로그인 세션 생성에 실패했습니다: ${error.message}',
      );
    }

    final session = authResponse.session;

    if (session == null) {
      throw const AuthFailure(
        '로그인 세션을 생성하지 못했습니다.',
      );
    }

    return session;
  }

  Future<void> signOut() {
    return _client.auth.signOut();
  }
}
