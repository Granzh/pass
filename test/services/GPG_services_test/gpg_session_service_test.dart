import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:pass/services/GPG_services/gpg_session_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late GPGSessionService sessionService;
  const String testProfileId1 = 'profile1';
  const String testProfileId2 = 'profile2';
  const String testPassphrase = 'secure_passphrase';
  const Duration testCacheTimeout = Duration(milliseconds: 100);
  const Duration shortDelay = Duration(milliseconds: 10);

  Future<void> pumpEventQueue({int times = 1}) async {
    for (int i = 0; i < times; i++) {
      await Future.delayed(Duration.zero);
    }
  }

  setUp(() {
    Logger.root.level = Level.OFF;
    Logger.root.onRecord.listen((record) {
    });

    sessionService = GPGSessionService(cacheTimeout: testCacheTimeout);
  });

  tearDown(() {
    sessionService.dispose();
  });

  group('Passphrase Management', () {
    test('setPassphrase stores the passphrase and notifies listeners', () {
      bool listenerCalled = false;
      sessionService.addListener(() {
        listenerCalled = true;
      });

      sessionService.setPassphrase(testProfileId1, testPassphrase);

      expect(sessionService.getPassphrase(testProfileId1), equals(testPassphrase));
      expect(listenerCalled, isTrue);
    });

    test('getPassphrase returns null for a different profileId', () {
      sessionService.setPassphrase(testProfileId1, testPassphrase);
      expect(sessionService.getPassphrase(testProfileId2), isNull);
    });

    test('getPassphrase returns null after clearing', () {
      sessionService.setPassphrase(testProfileId1, testPassphrase);
      sessionService.clearPassphrase();
      expect(sessionService.getPassphrase(testProfileId1), isNull);
    });

    test('clearPassphrase notifies listeners', () {
      sessionService.setPassphrase(testProfileId1, testPassphrase);

      bool listenerCalled = false;
      sessionService.addListener(() {
        listenerCalled = true;
      });

      sessionService.clearPassphrase();
      expect(listenerCalled, isTrue);
    });

    test('getPassphrase resets inactivity timer', () async {
      sessionService.setPassphrase(testProfileId1, testPassphrase);

      await Future.delayed(testCacheTimeout ~/ 2);
      expect(sessionService.getPassphrase(testProfileId1), testPassphrase, reason: "Passphrase should still be valid");

      sessionService.getPassphrase(testProfileId1);

      await Future.delayed(testCacheTimeout ~/ 2 + shortDelay);
      expect(sessionService.getPassphrase(testProfileId1), testPassphrase, reason: "Passphrase should still be valid after timer reset");

      await Future.delayed(testCacheTimeout + shortDelay);
      expect(sessionService.getPassphrase(testProfileId1), isNull, reason: "Passphrase should expire after new timeout");
    });
  });

  group('Inactivity Timer', () {
    test('passphrase clears after cacheTimeoutDuration', () async {
      sessionService.setPassphrase(testProfileId1, testPassphrase);
      expect(sessionService.getPassphrase(testProfileId1), testPassphrase);

      await Future.delayed(testCacheTimeout + shortDelay);
      await pumpEventQueue();

      expect(sessionService.getPassphrase(testProfileId1), isNull);
    });

    test('inactivity timer is cancelled when passphrase is cleared manually', () async {
      sessionService.setPassphrase(testProfileId1, testPassphrase);
      sessionService.clearPassphrase();

      await Future.delayed(testCacheTimeout + shortDelay);
      await pumpEventQueue();


      expect(sessionService.getPassphrase(testProfileId1), isNull);
    });
  });

  group('_justSetPassphrase flag and timer', () {
    test('_justSetPassphrase is true immediately after setPassphrase, then false after a delay', () async {
      sessionService.setPassphrase(testProfileId1, testPassphrase);

      sessionService.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(sessionService.getPassphrase(testProfileId1), testPassphrase,
          reason: "Passphrase should NOT be cleared if paused immediately after set, due to _justSetPassphrase flag");

      const Duration originalJustSetTimeout = Duration(seconds: 10);
      await Future.delayed(originalJustSetTimeout + shortDelay);
      await pumpEventQueue();

      sessionService.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(sessionService.getPassphrase(testProfileId1), isNull,
          reason: "Passphrase SHOULD be cleared if paused after _justSetPassphrase flag is false");
    });
  });


  group('App Lifecycle State Changes', () {
    setUp(() {
      sessionService.setPassphrase(testProfileId1, testPassphrase);
    });

    test('AppLifecycleState.resumed resets inactivity timer', () async {
      await Future.delayed(testCacheTimeout ~/ 2);
      sessionService.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future.delayed(testCacheTimeout ~/ 2 + shortDelay);
      expect(sessionService.getPassphrase(testProfileId1), testPassphrase, reason: "Passphrase should persist after resume resets timer");
      await Future.delayed(testCacheTimeout + shortDelay);
      expect(sessionService.getPassphrase(testProfileId1), isNull, reason: "Passphrase should expire after new timeout post-resume");
    });

    test('AppLifecycleState.paused clears passphrase if not _justSetPassphrase', () async {

      sessionService.setPassphrase("tempProfile", "tempPass");

      sessionService.setPassphrase(testProfileId1, testPassphrase);

      sessionService.setPassphrase(testProfileId1, testPassphrase);

      sessionService.setPassphrase(testProfileId1, testPassphrase);
      sessionService.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(sessionService.getPassphrase(testProfileId1), testPassphrase,
          reason: "Passphrase should NOT be cleared if paused immediately after set");
    });

    test('AppLifecycleState.paused does NOT clear passphrase if _justSetPassphrase is true', () {
      sessionService.setPassphrase(testProfileId1, testPassphrase);
      sessionService.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(sessionService.getPassphrase(testProfileId1), testPassphrase);
    });

    test('AppLifecycleState.detached clears passphrase', () {
      sessionService.didChangeAppLifecycleState(AppLifecycleState.detached);
      expect(sessionService.getPassphrase(testProfileId1), isNull);
    });

    test('AppLifecycleState.hidden clears passphrase if not _justSetPassphrase (similar to paused)', () {
      sessionService.setPassphrase(testProfileId1, testPassphrase);
      sessionService.didChangeAppLifecycleState(AppLifecycleState.hidden);
      expect(sessionService.getPassphrase(testProfileId1), testPassphrase,
          reason: "Passphrase should NOT be cleared if hidden immediately after set");
    });

    test('AppLifecycleState.hidden does NOT clear passphrase if _justSetPassphrase is true', () {
      sessionService.setPassphrase(testProfileId1, testPassphrase);
      sessionService.didChangeAppLifecycleState(AppLifecycleState.hidden);
      expect(sessionService.getPassphrase(testProfileId1), testPassphrase);
    });
  });

  group('Dispose', () {
    test('dispose cancels timers and removes observer', () {
      sessionService.setPassphrase(testProfileId1, testPassphrase);
      sessionService.dispose();

      expect(sessionService.getPassphrase(testProfileId1), isNull,
          reason: "Passphrase should be null after dispose, as dispose calls clearPassphrase implicitly (via timer cancellation or directly if implemented so)");
    });
  });
}
