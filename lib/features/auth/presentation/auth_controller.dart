import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/auth_repository.dart';

class AuthController extends ChangeNotifier {
  AuthController(this._repository);

  final AuthRepository _repository;

  bool _isLoading = false;
  String? _errorMessage;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Session? get session => _repository.currentSession;
  User? get user => _repository.currentUser;

  bool get isSignedIn => session != null;

  Future<bool> signIn({
    required String name,
    required String pin,
  }) async {
    if (_isLoading) {
      return false;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _repository.signInWithNameAndPin(
        name: name,
        pin: pin,
      );

      return true;
    } on AuthFailure catch (error) {
      _errorMessage = error.message;
      return false;
    } catch (_) {
      _errorMessage = '로그인 중 알 수 없는 오류가 발생했습니다.';
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    await _repository.signOut();
    _errorMessage = null;
    notifyListeners();
  }

  void clearError() {
    if (_errorMessage == null) {
      return;
    }

    _errorMessage = null;
    notifyListeners();
  }
}
