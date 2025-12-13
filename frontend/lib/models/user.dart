class User {
  final String id;
  final String email;
  final String displayName;
  final String role;
  final DateTime createdAt;

  User({
    required this.id,
    required this.email,
    required this.displayName,
    required this.role,
    required this.createdAt,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'],
      email: json['email'],
      displayName: json['display_name'],
      role: json['role'],
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}

class AuthToken {
  final String accessToken;
  final String tokenType;
  final User? user;

  AuthToken({
    required this.accessToken,
    this.tokenType = 'bearer',
    this.user,
  });

  factory AuthToken.fromJson(Map<String, dynamic> json) {
    return AuthToken(
      accessToken: json['access_token'],
      tokenType: json['token_type'] ?? 'bearer',
      user: json['user'] != null ? User.fromJson(json['user']) : null,
    );
  }
}
