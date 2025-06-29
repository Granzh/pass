class GPGKey {
  final String profileId;
  final String publicKey;
  final String privateKey;
  final String passphrase;

  GPGKey({
    required this.profileId,
    required this.publicKey,
    required this.privateKey,
    required this.passphrase
  });

  Map<String, dynamic> toJson() => {
    'publicKey': publicKey,
    'privateKey': privateKey,
    'passphrase': passphrase,
  };

  factory GPGKey.fromJson(String profileId, Map<String, dynamic> json) => GPGKey(
      profileId: profileId,
      publicKey: json['publicKey'],
      privateKey: json['privateKey'],
      passphrase: json['passphrase'],
  );
}