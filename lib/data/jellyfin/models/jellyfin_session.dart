class JellyfinSession {
  const JellyfinSession({
    required this.serverUrl,
    required this.accessToken,
    required this.userId,
    required this.serverId,
    required this.username,
  });

  final String serverUrl;
  final String accessToken;
  final String userId;
  final String serverId;
  final String username;

  Map<String, dynamic> toJson() => {
    'serverUrl': serverUrl,
    'accessToken': accessToken,
    'userId': userId,
    'serverId': serverId,
    'username': username,
  };

  factory JellyfinSession.fromJson(Map<String, dynamic> json) {
    return JellyfinSession(
      serverUrl: json['serverUrl'] as String,
      accessToken: json['accessToken'] as String,
      userId: json['userId'] as String,
      serverId: json['serverId'] as String,
      username: json['username'] as String,
    );
  }
}
