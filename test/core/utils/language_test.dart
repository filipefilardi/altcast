import 'package:flutter_test/flutter_test.dart';

import 'package:altcast/core/utils/language.dart';

void main() {
  group('languageCodesMatch', () {
    test('matches ISO aliases for the same language', () {
      expect(languageCodesMatch('pt', 'por'), isTrue);
      expect(languageCodesMatch('en', 'eng'), isTrue);
    });

    test('matches display names against language codes', () {
      expect(languageCodesMatch('Portuguese', 'pt'), isTrue);
      expect(languageCodesMatch('English', 'eng'), isTrue);
    });

    test('matches region-specific codes by base language', () {
      expect(languageCodesMatch('pt-BR', 'pt'), isTrue);
      expect(languageCodesMatch('en_US', 'eng'), isTrue);
    });

    test('does not match unknown or different languages', () {
      expect(languageCodesMatch('Portuguese', 'en'), isFalse);
      expect(languageCodesMatch('und', 'pt'), isFalse);
    });
  });
}
