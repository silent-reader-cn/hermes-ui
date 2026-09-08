import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/update/version_info.dart';

void main() {
  group('version_info', () {
    test('appVersion matches expected pubspec baseline version', () {
      expect(appVersion, '0.1.30');
    });

    group('newer() semver comparison', () {
      test('1.2.3 is newer than 1.2.2', () {
        expect(newer('1.2.3', '1.2.2'), isTrue);
      });

      test('1.10.0 is newer than 1.9.9', () {
        expect(newer('1.10.0', '1.9.9'), isTrue);
      });

      test('same version returns false (no update)', () {
        expect(newer('1.2.3', '1.2.3'), isFalse);
      });

      test('older version returns false', () {
        expect(newer('1.2.2', '1.2.3'), isFalse);
        expect(newer('0.1.29', '0.1.30'), isFalse);
      });

      test('tag v-prefix tolerance: v1.2.3 == 1.2.3 (no update)', () {
        expect(newer('v1.2.3', '1.2.3'), isFalse);
        expect(newer('1.2.3', 'v1.2.3'), isFalse);
      });

      test('tag v-prefix tolerance: v1.2.4 is newer than 1.2.3', () {
        expect(newer('v1.2.4', '1.2.3'), isTrue);
        expect(newer('1.2.4', 'v1.2.3'), isTrue);
      });

      test('tag uppercase V-prefix tolerance: V2.0.0 > 1.9.9', () {
        expect(newer('V2.0.0', '1.9.9'), isTrue);
      });

      test('build number tolerance: 0.1.30+33 vs 0.1.30 is false', () {
        expect(newer('0.1.30+33', '0.1.30'), isFalse);
        expect(newer('0.1.30', '0.1.30+33'), isFalse);
      });

      test('build number tolerance: 0.1.31 is newer than 0.1.30+33', () {
        expect(newer('0.1.31', '0.1.30+33'), isTrue);
      });

      test('major bump: 2.0.0 is newer than 1.99.99', () {
        expect(newer('2.0.0', '1.99.99'), isTrue);
      });

      test('minor bump: 0.2.0 is newer than 0.1.99', () {
        expect(newer('0.2.0', '0.1.99'), isTrue);
      });

      test('prerelease tolerance: 0.1.31-beta is newer than 0.1.30', () {
        expect(newer('0.1.31-beta', '0.1.30'), isTrue);
      });

      test('malformed/empty input returns false safely', () {
        expect(newer('', '0.1.30'), isFalse);
        expect(newer('0.1.30', ''), isFalse);
        expect(newer('', ''), isFalse);
        expect(newer('invalid', '0.1.30'), isFalse);
        expect(newer('0.1.30', 'invalid'), isFalse);
        expect(newer('v', '0.1.30'), isFalse);
      });
    });

    group('cleanVersionParts()', () {
      test('parses standard semver', () {
        expect(cleanVersionParts('1.2.3'), [1, 2, 3]);
        expect(cleanVersionParts('v0.1.30'), [0, 1, 30]);
      });

      test('pads short versions to length 3', () {
        expect(cleanVersionParts('1.0'), [1, 0, 0]);
        expect(cleanVersionParts('2'), [2, 0, 0]);
      });

      test('returns null for empty or invalid', () {
        expect(cleanVersionParts(''), isNull);
        expect(cleanVersionParts('abc'), isNull);
      });
    });
  });
}
