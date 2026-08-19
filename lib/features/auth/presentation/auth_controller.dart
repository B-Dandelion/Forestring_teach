import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/auth_repository.dart';
import '../domain/current_profile.dart';

class AuthController extends ChangeNotifier {
  AuthController(this._repository);

  final AuthRepository _repository;

  bool _isInitializing = true;
  bool _isLoading = false;

  String? _errorMessage;

  CurrentProfile? _profile;

  bool get isInitializing => _isInitializing;

  bool get isLoading => _isLoading;

  String? get errorMessage => _errorMessage;

  CurrentProfile? get profile => _profile;

  Session? get session => _repository.currentSession;

  User? get user => _repository.currentUser;

  bool get isSignedIn => session != null && _profile != null;

  Future<void> initialize() async {
    _isInitializing = true;
    _errorMessage = null;

    try {
      if (_repository.currentSession == null) {
        _profile = null;
        return;
      }

      _profile = await _repository.fetchCurrentProfile();
    } on AuthFailure catch (error) {
      _profile = null;

      await _repository.signOut();

      _errorMessage = error.message;
    } catch (_) {
      _profile = null;

      await _repository.signOut();

      _errorMessage = '로그인 정보를 확인하지 못했습니다.';
    } finally {
      _isInitializing = false;
      notifyListeners();
    }
  }

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

      _profile = await _repository.fetchCurrentProfile();

      return true;
    } on AuthFailure catch (error) {
      _profile = null;

      if (_repository.currentSession != null) {
        await _repository.signOut();
      }

      _errorMessage = error.message;

      return false;
    } catch (_) {
      _profile = null;

      if (_repository.currentSession != null) {
        await _repository.signOut();
      }

      _errorMessage = '로그인 중 알 수 없는 오류가 발생했습니다.';

      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    await _repository.signOut();

    _profile = null;
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
