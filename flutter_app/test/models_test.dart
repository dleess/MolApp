import 'package:flutter_test/flutter_test.dart';
import 'package:molapp/src/models.dart';
import 'package:molapp/src/structure_file.dart';

void main() {
  group('PdbIdentifier', () {
    test('normalizes valid input', () {
      expect(PdbIdentifier.normalized(' 1abc '), '1ABC');
      expect(PdbIdentifier.normalized('7tim'), '7TIM');
    });

    test('rejects invalid input', () {
      expect(() => PdbIdentifier.normalized('abc'), throwsA(isA<PdbIdentifierException>()));
      expect(() => PdbIdentifier.normalized('12-4'), throwsA(isA<PdbIdentifierException>()));
      expect(() => PdbIdentifier.normalized('12345'), throwsA(isA<PdbIdentifierException>()));
    });

    test('displayName falls back to the trimmed uppercase input', () {
      expect(PdbIdentifier.displayName(' abc '), 'ABC');
      expect(PdbIdentifier.displayName('1abc'), '1ABC');
    });
  });

  group('LocalStructureFileLoader.formatFor', () {
    test('maps supported extensions', () {
      expect(LocalStructureFileLoader.formatFor('model.pdb'), 'pdb');
      expect(LocalStructureFileLoader.formatFor('model.cif'), 'mmcif');
      expect(LocalStructureFileLoader.formatFor('model.mmcif'), 'mmcif');
      expect(LocalStructureFileLoader.formatFor('MODEL.PDB'), 'pdb');
    });

    test('rejects an unsupported extension by name', () {
      expect(
        () => LocalStructureFileLoader.formatFor('model.txt'),
        throwsA(
          isA<StructureFileException>().having((e) => e.message, 'message', contains('.txt')),
        ),
      );
    });

    test('rejects a file with no extension', () {
      expect(
        () => LocalStructureFileLoader.formatFor('model'),
        throwsA(
          isA<StructureFileException>()
              .having((e) => e.message, 'message', contains('selected file')),
        ),
      );
    });
  });

  group('wire-format contracts', () {
    // Enum names ARE the payload keys viewer.html switches on; renaming a value silently breaks
    // the corresponding command, so pin the names themselves.
    test('visibility feature keys', () {
      expect(MoleculeVisibilityFeature.values.map((e) => e.name), <String>[
        'protein',
        'water',
        'ligand',
      ]);
    });

    test('object representation wire names', () {
      expect(ObjectRepresentation.values.map((e) => e.name), <String>[
        'ribbon',
        'surface',
        'stick',
        'ballAndStick',
        'sphere',
      ]);
    });

    test('scene representation wire names', () {
      expect(MoleculeRepresentation.values.map((e) => e.name), <String>[
        'ribbon',
        'surface',
        'stick',
      ]);
    });

    test('measure kind wire names', () {
      expect(MeasureKind.values.map((e) => e.name), <String>['distance', 'angle', 'dihedral']);
    });

    test('measure kinds carry the pick count', () {
      expect(MeasureKind.distance.atomCount, 2);
      expect(MeasureKind.angle.atomCount, 3);
      expect(MeasureKind.dihedral.atomCount, 4);
    });
  });

  group('MolAppObject', () {
    test('defaults to a visible ribbon with no color override', () {
      const object = MolAppObject(name: '1crn', type: MolAppObjectType.structure);
      expect(object.isVisible, isTrue);
      expect(object.representation, ObjectRepresentation.ribbon);
      expect(object.colorHex, isNull);
    });

    test('copyWith can clear the color back to the Mol* default', () {
      const object = MolAppObject(
        name: '1crn',
        type: MolAppObjectType.structure,
        colorHex: '#D55E00',
      );
      expect(object.copyWith(clearColor: true).colorHex, isNull);
      expect(object.copyWith(isVisible: false).colorHex, '#D55E00');
    });
  });

  group('colorFromHex', () {
    test('parses #RRGGBB', () {
      expect(colorFromHex('#D55E00')?.toARGB32(), 0xFFD55E00);
    });

    test('returns null for a malformed value', () {
      expect(colorFromHex(null), isNull);
      expect(colorFromHex('#GGG'), isNull);
      expect(colorFromHex('nonsense'), isNull);
    });
  });

  group('palette', () {
    test('every color-picker key except default maps to a named color', () {
      for (final key in colorPickerKeys.where((k) => k != 'default')) {
        expect(namedColors[key], isNotNull, reason: key);
        expect(colorFromHex(namedColors[key]), isNotNull, reason: key);
      }
    });

    test('background presets are all valid hex', () {
      for (final preset in backgroundPresets) {
        expect(RegExp(r'^#[0-9A-F]{6}$').hasMatch(preset.hex), isTrue, reason: preset.title);
      }
    });
  });
}
