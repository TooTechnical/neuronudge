import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/services/ai_service.dart';

void main() {
  test('HTTP errors retain a safe status and message', () {
    const error = HttpException(401, 'Authentication required');

    expect(error.statusCode, 401);
    expect(error.toString(), contains('Authentication required'));
  });

  test('development API URL has an explicit local default', () {
    expect(AIService.baseUrl, 'http://127.0.0.1:8000');
  });
}
