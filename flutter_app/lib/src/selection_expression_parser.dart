import 'models.dart';

class SelectionParseException implements Exception {
  const SelectionParseException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Recursive-descent parser for the `select` command's expression language:
///
///     chain A & res 3-42 | !resn HOH
///
/// A direct port of the Swift/Linux parsers — the three must stay in step because they all produce
/// the same AST for `queryFromAST` in viewer.html.
class SelectionExpressionParser {
  SelectionExpressionParser(String expression) : _tokens = _tokenize(expression);

  final List<String> _tokens;
  int _index = 0;

  static const List<String> symbols = <String>['&', '|', '!', '(', ')'];

  static const Set<String> selectionKeywords = <String>{
    'chain',
    'residue',
    'res',
    'resn',
    'atom',
    'model',
    'not',
    'and',
    'or',
  };

  static List<String> _tokenize(String expression) {
    var expr = expression;
    for (final symbol in symbols) {
      expr = expr.replaceAll(symbol, ' $symbol ');
    }
    return expr.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
  }

  SelectionAST parse() {
    final ast = _parseOr();
    if (_index < _tokens.length) {
      throw SelectionParseException('Unexpected token: ${_tokens[_index]}');
    }
    return ast;
  }

  SelectionAST _parseOr() {
    var node = _parseAnd();
    while (_index < _tokens.length &&
        (_tokens[_index] == '|' || _tokens[_index].toLowerCase() == 'or')) {
      _index += 1;
      final right = _parseAnd();
      node = SelectionAST(
        kind: SelectionASTKind.or,
        left: <SelectionAST>[node],
        right: <SelectionAST>[right],
      );
    }
    return node;
  }

  SelectionAST _parseAnd() {
    var node = _parseNot();
    while (_index < _tokens.length &&
        (_tokens[_index] == '&' || _tokens[_index].toLowerCase() == 'and')) {
      _index += 1;
      final right = _parseNot();
      node = SelectionAST(
        kind: SelectionASTKind.and,
        left: <SelectionAST>[node],
        right: <SelectionAST>[right],
      );
    }
    return node;
  }

  SelectionAST _parseNot() {
    if (_index < _tokens.length &&
        (_tokens[_index] == '!' || _tokens[_index].toLowerCase() == 'not')) {
      _index += 1;
      final operand = _parseNot();
      return SelectionAST(
        kind: SelectionASTKind.not,
        operand: <SelectionAST>[operand],
      );
    }
    return _parsePrimary();
  }

  SelectionAST _parsePrimary() {
    if (_index >= _tokens.length) {
      throw const SelectionParseException('Unexpected end of expression');
    }

    final raw = _tokens[_index];
    final token = raw.toLowerCase();

    if (token == '(') {
      _index += 1;
      final node = _parseOr();
      if (_index >= _tokens.length || _tokens[_index] != ')') {
        throw const SelectionParseException('Missing closing parenthesis');
      }
      _index += 1;
      return node;
    }

    if (token == 'chain') {
      // Preserve case: chain IDs are case-sensitive (e.g. distinct A vs a in large assemblies).
      return SelectionAST(
        kind: SelectionASTKind.chain,
        value: _valueFor(token),
      );
    } else if (token == 'atom') {
      return SelectionAST(
        kind: SelectionASTKind.atom,
        value: _valueFor(token).toUpperCase(),
      );
    } else if (token == 'res' || token == 'residue' || token == 'model') {
      final value = _valueFor(token);
      if (RegExp(r'^[+-]?[0-9]+$').hasMatch(value)) {
        return SelectionAST(
          kind: token == 'model'
              ? SelectionASTKind.model
              : SelectionASTKind.residue,
          value: value,
        );
      }
      if (token != 'model' && RegExp(r'^-?[0-9]+--?[0-9]+$').hasMatch(value)) {
        return SelectionAST(kind: SelectionASTKind.residueRange, value: value);
      }
      throw SelectionParseException('Invalid value for $token: $value');
    } else if (token == 'resn') {
      return SelectionAST(
        kind: SelectionASTKind.residueName,
        value: _valueFor(token).toUpperCase(),
      );
    }

    throw SelectionParseException('Unexpected token: $token');
  }

  String _valueFor(String keyword) {
    _index += 1;
    if (_index >= _tokens.length || symbols.contains(_tokens[_index])) {
      throw SelectionParseException('Missing value for $keyword');
    }
    return _tokens[_index++];
  }

  /// Splits `select sele chain A` into the object name and the expression. A leading token that is
  /// not a keyword and carries no tokenizer symbol is the name; otherwise the selection is "sele".
  static (String name, String expression) extractName(String afterSelect) {
    final parts = afterSelect.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    // A name cannot contain a tokenizer symbol: the tokenizer would split it, so it was never one name.
    final symbolChars = symbols.join();
    if (parts.length >= 2 &&
        !selectionKeywords.contains(parts[0].toLowerCase()) &&
        !parts[0].split('').any(symbolChars.contains)) {
      return (parts[0], parts.skip(1).join(' '));
    }
    return ('sele', afterSelect);
  }
}
