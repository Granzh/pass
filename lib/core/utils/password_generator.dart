import 'dart:math';

String generateSecurePassword({
  int length = 16,
  bool includeUppercase = true,
  bool includeLowercase = true,
  bool includeNumbers = true,
  bool includeSymbols = true,
}) {

  if (length <= 0) {
    throw ArgumentError('Password length must be positive.');
  }

  final selectedCharTypes = <String>[];
  final StringBuffer allCharsPool = StringBuffer();

  const String uppercaseChars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  const String lowercaseChars = 'abcdefghijklmnopqrstuvwxyz';
  const String numberChars = '0123456789';
  const String symbolChars = '!@#\$%^&*()_+-=[]{};:,./<>?';

  if (includeUppercase) {
    selectedCharTypes.add(uppercaseChars);
    allCharsPool.write(uppercaseChars);
  }
  if (includeLowercase) {
    selectedCharTypes.add(lowercaseChars);
    allCharsPool.write(lowercaseChars);
  }
  if (includeNumbers) {
    selectedCharTypes.add(numberChars);
    allCharsPool.write(numberChars);
  }
  if (includeSymbols) {
    selectedCharTypes.add(symbolChars);
    allCharsPool.write(symbolChars);
  }

  if (selectedCharTypes.isEmpty) {
    throw ArgumentError('At least one character type must be included.');
  }
  if (length < selectedCharTypes.length) {
    throw ArgumentError(
        'Password length ($length) is too short to include all selected character types (${selectedCharTypes.length}).');
  }

  final random = Random.secure();
  final List<String> passwordChars = [];

  for (final charTypeString in selectedCharTypes) {
    passwordChars.add(charTypeString[random.nextInt(charTypeString.length)]);
  }

  final remainingLength = length - passwordChars.length;
  if (remainingLength > 0) {
    final allCharsString = allCharsPool.toString();
    for (int i = 0; i < remainingLength; i++) {
      passwordChars.add(allCharsString[random.nextInt(allCharsString.length)]);
    }
  }

  passwordChars.shuffle(random);

  return passwordChars.join();
}