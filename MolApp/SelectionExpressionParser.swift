import Foundation

struct SelectionExpressionParser {
    let tokens: [String]
    var index = 0

    static let symbols = ["&", "|", "!", "(", ")"]

    init(expression: String) {
        var expr = expression
        for s in Self.symbols {
            expr = expr.replacingOccurrences(of: s, with: " \(s) ")
        }
        self.tokens = expr.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
    }

    mutating func parse() throws -> SelectionAST {
        let ast = try parseOr()
        if index < tokens.count {
            throw ParserError.unexpectedToken(tokens[index])
        }
        return ast
    }

    private mutating func parseOr() throws -> SelectionAST {
        var node = try parseAnd()
        while index < tokens.count && (tokens[index] == "|" || tokens[index].lowercased() == "or") {
            index += 1
            let right = try parseAnd()
            node = SelectionAST(kind: .or, left: [node], right: [right], operand: nil, value: nil)
        }
        return node
    }

    private mutating func parseAnd() throws -> SelectionAST {
        var node = try parseNot()
        while index < tokens.count && (tokens[index] == "&" || tokens[index].lowercased() == "and") {
            index += 1
            let right = try parseNot()
            node = SelectionAST(kind: .and, left: [node], right: [right], operand: nil, value: nil)
        }
        return node
    }

    private mutating func parseNot() throws -> SelectionAST {
        if index < tokens.count && (tokens[index] == "!" || tokens[index].lowercased() == "not") {
            index += 1
            let operand = try parseNot()
            return SelectionAST(kind: .not, left: nil, right: nil, operand: [operand], value: nil)
        }
        return try parsePrimary()
    }

    private mutating func parsePrimary() throws -> SelectionAST {
        guard index < tokens.count else {
            throw ParserError.unexpectedEOF
        }

        let raw = tokens[index]
        let token = raw.lowercased()
        if token == "(" {
            index += 1
            let node = try parseOr()
            guard index < tokens.count && tokens[index] == ")" else {
                throw ParserError.missingClosingParen
            }
            index += 1
            return node
        }

        var kind: SelectionAST.Kind
        switch token {
        case "chain": kind = .chain
        case "atom": kind = .atom
        case "res", "residue": kind = .residue
        case "resn": kind = .residueName
        case "model": kind = .model
        default: throw ParserError.unexpectedToken(token)
        }
        index += 1
        guard index < tokens.count, !Self.symbols.contains(tokens[index]) else {
            throw ParserError.missingValue(token)
        }
        var value = tokens[index]
        index += 1
        if kind == .residue || kind == .model {
            if kind == .residue, value.range(of: #"^-?[0-9]+--?[0-9]+$"#, options: .regularExpression) != nil {
                kind = .residueRange
            } else if value.range(of: #"^[+-]?[0-9]+$"#, options: .regularExpression) == nil {
                throw ParserError.invalidValue(token, value)
            }
        } else if kind == .atom || kind == .residueName {
            value = value.uppercased()
        }
        // Preserve case for chain IDs, including keyword-like IDs such as "and".
        return SelectionAST(kind: kind, left: nil, right: nil, operand: nil, value: value)
    }

    static let selectionKeywords: Set<String> = [
        "chain", "residue", "res", "resn", "atom", "model", "not", "and", "or"
    ]

    static func extractName(from afterSelect: String) -> (name: String, expression: String) {
        let parts = afterSelect.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        // A name cannot contain a tokenizer symbol: the tokenizer would split it, so it was never one name.
        let symbolChars = Set(symbols.joined())
        if parts.count >= 2 && !selectionKeywords.contains(parts[0].lowercased())
            && !parts[0].contains(where: { symbolChars.contains($0) }) {
            return (parts[0], parts.dropFirst().joined(separator: " "))
        }
        return ("sele", afterSelect)
    }

    enum ParserError: Error, LocalizedError {
        case unexpectedToken(String)
        case unexpectedEOF
        case missingClosingParen
        case missingValue(String)
        case invalidValue(String, String)

        var errorDescription: String? {
            switch self {
            case .unexpectedToken(let t): "Unexpected token: \(t)"
            case .unexpectedEOF: "Unexpected end of expression"
            case .missingClosingParen: "Missing closing parenthesis"
            case .missingValue(let t): "Missing value for \(t)"
            case .invalidValue(let t, let value): "Invalid value for \(t): \(value)"
            }
        }
    }
}

extension String {
    func dropping(first count: Int) -> String {
        guard count <= self.count else { return "" }
        return String(self.dropFirst(count))
    }
}
