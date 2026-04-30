import 'package:dio/dio.dart';

String _truncateHint(String text, {int maxLen = 140}) {
  final t = text.trim();
  if (t.length <= maxLen) return t;
  return '${t.substring(0, maxLen - 1)}…';
}

/// Plain-text or JSON snippet from Jellyfin’s response body, if useful.
String? _responseBodyHint(Response<dynamic>? response) {
  if (response == null) return null;
  final data = response.data;
  if (data is String) {
    final t = data.trim();
    return t.isEmpty ? null : _truncateHint(t);
  }
  if (data is Map) {
    for (final key in ['Message', 'message', 'error', 'title']) {
      final v = data[key];
      if (v is String && v.trim().isNotEmpty) {
        return _truncateHint(v);
      }
    }
  }
  return null;
}

/// Short, user-readable explanation for HTTP/network failures from Dio.
String userFacingDioMessage(DioException e) {
  final status = e.response?.statusCode;
  if (status == 401) {
    return 'Invalid username or password.';
  }
  if (e.type == DioExceptionType.badCertificate) {
    return 'HTTPS certificate could not be verified (common with self-signed certs). '
        'Try http:// if your server allows plain HTTP, or use a trusted certificate.';
  }
  if (e.type == DioExceptionType.connectionTimeout ||
      e.type == DioExceptionType.receiveTimeout ||
      e.type == DioExceptionType.sendTimeout ||
      e.type == DioExceptionType.connectionError) {
    return 'Could not reach server. Check the URL and your network.';
  }
  if (status != null && status >= 500) {
    final method = e.requestOptions.method.toUpperCase();
    final path = e.requestOptions.path;
    final where = path.isEmpty ? method : '$method $path';
    final hint = _responseBodyHint(e.response);
    final buf = StringBuffer(
      'Your Jellyfin server returned an error (HTTP $status) on $where.',
    );
    if (hint != null) {
      buf.write(' Server said: $hint');
    }
    buf.write(
      ' In Jellyfin: Dashboard → Logs — search for this path or the same time; '
      'plugins and library issues are common causes.',
    );
    return buf.toString();
  }
  if (status == 403) {
    return 'Access denied.';
  }
  if (status == 404) {
    return 'Not found. Check the server URL and that Jellyfin is running.';
  }
  return e.message ?? 'Network error.';
}

/// Uses [userFacingDioMessage] for [DioException], otherwise [Object.toString].
String userFacingNetworkMessage(Object error) {
  if (error is DioException) return userFacingDioMessage(error);
  return error.toString();
}
