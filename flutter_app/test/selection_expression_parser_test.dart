import 'package:flutter_test/flutter_test.dart';
import 'package:molapp/src/models.dart';
import 'package:molapp/src/selection_expression_parser.dart';

SelectionAST parse(String expression) => SelectionExpressionParser(expression).parse();

void main() {
  group('SelectionExpressionParser', () {
    test('handles basic terms', () {
      final ast = parse('chain A');
      expect(ast.kind, SelectionASTKind.chain);
      expect(ast.value, 'A');
    });

    test('handles the not operator', () {
      final ast = parse('!chain A');
      expect(ast.kind, SelectionASTKind.not);
      expect(ast.operand![0].kind, SelectionASTKind.chain);
      expect(ast.operand![0].value, 'A');
    });

    test('handles the and operator', () {
      final ast = parse('chain A & residue 10');
      expect(ast.kind, SelectionASTKind.and);
      expect(ast.left![0].kind, SelectionASTKind.chain);
      expect(ast.left![0].value, 'A');
      expect(ast.right![0].kind, SelectionASTKind.residue);
      expect(ast.right![0].value, '10');
    });

    test('handles the or operator', () {
      final ast = parse('chain A | chain B');
      expect(ast.kind, SelectionASTKind.or);
      expect(ast.left![0].value, 'A');
      expect(ast.right![0].value, 'B');
    });

    test('binds and tighter than or', () {
      final ast = parse('chain A | chain B & residue 10');
      expect(ast.kind, SelectionASTKind.or);
      expect(ast.left![0].value, 'A');
      expect(ast.right![0].kind, SelectionASTKind.and);
    });

    test('handles parentheses', () {
      final ast = parse('(chain A | chain B) & residue 10');
      expect(ast.kind, SelectionASTKind.and);
      expect(ast.left![0].kind, SelectionASTKind.or);
      expect(ast.right![0].kind, SelectionASTKind.residue);
    });

    test('throws on invalid input', () {
      expect(() => parse('chain A &'), throwsA(isA<SelectionParseException>()));
      expect(() => parse('(chain A'), throwsA(isA<SelectionParseException>()));
      expect(() => parse('unknown term'), throwsA(isA<SelectionParseException>()));
      expect(() => parse('chain'), throwsA(isA<SelectionParseException>()));
    });

    test('reads res as a single residue', () {
      final ast = parse('res 42');
      expect(ast.kind, SelectionASTKind.residue);
      expect(ast.value, '42');
    });

    test('reads res as a range', () {
      final ast = parse('res 3-42');
      expect(ast.kind, SelectionASTKind.residueRange);
      expect(ast.value, '3-42');
    });

    // `residue` is an alias for `res`, so it must range-check too: emitting residue("10-20") makes
    // the JS side prefix-parse it to residue 10 alone, with no error.
    test('reads the residue alias as a range', () {
      final ast = parse('residue 10-20');
      expect(ast.kind, SelectionASTKind.residueRange);
      expect(ast.value, '10-20');
    });

    test('reads the residue alias as a single residue', () {
      final ast = parse('residue 42');
      expect(ast.kind, SelectionASTKind.residue);
      expect(ast.value, '42');
    });

    test('treats a negative res as a single residue', () {
      final ast = parse('res -5');
      expect(ast.kind, SelectionASTKind.residue);
      expect(ast.value, '-5');
    });

    test('handles a negative-bounded range', () {
      final ast = parse('res -5-10');
      expect(ast.kind, SelectionASTKind.residueRange);
      expect(ast.value, '-5-10');
    });

    test('handles the not text keyword', () {
      final ast = parse('not chain a');
      expect(ast.kind, SelectionASTKind.not);
      expect(ast.operand![0].kind, SelectionASTKind.chain);
      expect(ast.operand![0].value, 'a');
    });

    test('preserves chain case', () {
      expect(parse('chain a').value, 'a');
      final ast = parse('CHAIN B');
      expect(ast.kind, SelectionASTKind.chain);
      expect(ast.value, 'B');
    });

    test('uppercases resn', () {
      final ast = parse('resn ala');
      expect(ast.kind, SelectionASTKind.residueName);
      expect(ast.value, 'ALA');
    });

    test('uppercases atom names', () {
      final ast = parse('atom ca');
      expect(ast.kind, SelectionASTKind.atom);
      expect(ast.value, 'CA');
    });

    test('handles model terms', () {
      final ast = parse('model 2');
      expect(ast.kind, SelectionASTKind.model);
      expect(ast.value, '2');
    });

    test('handles the and text keyword', () {
      final ast = parse('chain a and res 10');
      expect(ast.kind, SelectionASTKind.and);
      expect(ast.left![0].kind, SelectionASTKind.chain);
      expect(ast.right![0].kind, SelectionASTKind.residue);
    });

    test('handles the or text keyword', () {
      final ast = parse('chain a or chain b');
      expect(ast.kind, SelectionASTKind.or);
      expect(ast.left![0].value, 'a');
      expect(ast.right![0].value, 'b');
    });
  });

  group('extractName', () {
    test('takes a leading non-keyword token as the name', () {
      final (name, expression) = SelectionExpressionParser.extractName('mysel chain A');
      expect(name, 'mysel');
      expect(expression, 'chain A');
    });

    test('defaults to sele when the expression starts with a keyword', () {
      final (name, expression) = SelectionExpressionParser.extractName('chain A');
      expect(name, 'sele');
      expect(expression, 'chain A');
    });

    // A symbol operator must never be mistaken for a selection name: naming the selection "!" would
    // drop the negation and silently select the complement of what was asked.
    test('defaults to sele for a leading symbol operator', () {
      for (final expression in <String>['! chain A', '(chain A | chain B)', '!chain A']) {
        final (name, parsed) = SelectionExpressionParser.extractName(expression);
        expect(name, 'sele', reason: 'expression: $expression');
        expect(parsed, expression, reason: 'expression: $expression');
      }
    });

    test('still accepts an explicit name before a symbol operator', () {
      final (name, expression) = SelectionExpressionParser.extractName('mysel ! chain A');
      expect(name, 'mysel');
      expect(expression, '! chain A');
    });
  });

  group('AST wire format', () {
    test('omits null fields and nests operands in single-element lists', () {
      final ast = parse('chain A & res 10');
      expect(ast.toJson(), <String, dynamic>{
        'kind': 'and',
        'left': <dynamic>[
          <String, dynamic>{'kind': 'chain', 'value': 'A'},
        ],
        'right': <dynamic>[
          <String, dynamic>{'kind': 'residue', 'value': '10'},
        ],
      });
    });

    test('encodes not with an operand list', () {
      expect(parse('!chain A').toJson(), <String, dynamic>{
        'kind': 'not',
        'operand': <dynamic>[
          <String, dynamic>{'kind': 'chain', 'value': 'A'},
        ],
      });
    });
  });
}
