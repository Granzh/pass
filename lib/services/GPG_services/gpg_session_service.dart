import 'dart:async';

import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

class GPGSessionService extends ChangeNotifier with WidgetsBindingObserver {
  static final _log = Logger('GPGSessionService');

  String? _cachedPassphrase;
  Timer? _inactivityTimer;
  final Duration _cacheTimeoutDuration;

  String? _currentProfileId;

  bool _justSetPassphrase = false;
  Timer? _justSetPassphraseClearTimer;

  GPGSessionService({Duration cacheTimeout = const Duration(minutes: 5)})
      : _cacheTimeoutDuration = cacheTimeout {
    WidgetsBinding.instance.addObserver(this);
    _log.info("GpgSessionService initialized. Cache timeout: $_cacheTimeoutDuration");
  }

  String? getPassphrase(String profileId) {
    if (_currentProfileId == profileId && _cachedPassphrase != null) {
      _log.fine("Accessing cached GPG passphrase for profile '$profileId'.");
      _resetInactivityTimer();
      return _cachedPassphrase;
    }
    _log.fine("No valid cached GPG passphrase found for profile '$profileId'.");
    return null;
  }

  void setPassphrase(String profileId, String passphrase) {
    _currentProfileId = profileId;
    _cachedPassphrase = passphrase;
    _justSetPassphrase = true;
    _justSetPassphraseClearTimer?.cancel();
    _justSetPassphraseClearTimer = Timer(const Duration(seconds: 10), () {
      _justSetPassphrase = false;
    });

    _log.info("GPG passphrase cached for profile '$profileId'.");
    _resetInactivityTimer();
    notifyListeners();
  }


  void clearPassphrase({String? reason}) {
    if (_cachedPassphrase != null) {
      _log.info("GPG passphrase cache cleared for profile '$_currentProfileId'. Reason: ${reason ?? 'Unknown'}.");
    }
    _cachedPassphrase = null;
    _currentProfileId = null;
    _inactivityTimer?.cancel();
    _inactivityTimer = null;
    _justSetPassphrase = false;
    _justSetPassphraseClearTimer?.cancel();
    notifyListeners();
  }

  void _resetInactivityTimer() {
    _inactivityTimer?.cancel();
    if (_cachedPassphrase != null) {
      _log.fine("Resetting GPG passphrase inactivity timer (${_cacheTimeoutDuration.inMinutes} min).");
      _inactivityTimer = Timer(_cacheTimeoutDuration, () {
        _log.info("GPG passphrase cache timed out due to inactivity.");
        clearPassphrase(reason: "Inactivity timeout");
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    _log.info("App lifecycle state changed to: $state");
    switch (state) {
      case AppLifecycleState.resumed:
        _log.fine("App resumed. GPG passphrase cache state check.");
        if (_cachedPassphrase != null) {
          _resetInactivityTimer();
        }
        break;
      case AppLifecycleState.inactive:

        _log.fine("App inactive. Inactivity timer continues.");
        break;
      case AppLifecycleState.paused:
        if (!_justSetPassphrase) {
          _log.info("App paused. Clearing GPG passphrase cache as a security measure.");
          clearPassphrase(reason: "App paused");
        } else {
          _log.info("App paused, but passphrase was just set. Cache will persist for a short duration or until timeout.");
        }
        break;
      case AppLifecycleState.detached:

        _log.info("App detached. Clearing GPG passphrase cache.");
        clearPassphrase(reason: "App detached");
        break;
      case AppLifecycleState.hidden:
        _log.info("App hidden. Applying similar logic to 'paused'.");
        if (!_justSetPassphrase) {
          _log.info("App hidden. Clearing GPG passphrase cache as a security measure.");
          clearPassphrase(reason: "App hidden");
        } else {
          _log.info("App hidden, but passphrase was just set. Cache will persist for a short duration or until timeout.");
        }
        break;
    }
  }

  @override
  void dispose() {
    _log.info("GpgSessionService disposed.");
    _inactivityTimer?.cancel();
    _justSetPassphraseClearTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}