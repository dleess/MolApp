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

        if token == "chain" {
            index += 1
            guard index < tokens.count else { throw ParserError.missingValue("chain") }
            // Preserve case: chain IDs are case-sensitive (e.g. distinct A vs a in large assemblies).
            let value = tokens[index]
            index += 1
            return SelectionAST(kind: .chain, left: nil, right: nil, operand: nil, value: value)
        } else if token == "atom" {
            index += 1
            guard index < tokens.count else { throw ParserError.missingValue("atom") }
            let value = tokens[index].uppercased()
            index += 1
            return SelectionAST(kind: .atom, left: nil, right: nil, operand: nil, value: value)
        } else if token == "res" || token == "residue" {
            index += 1
            guard index < tokens.count else { throw ParserError.missingValue(token) }
            let value = tokens[index]
            index += 1
            // A range needs an interior hyphen ("3-42"); a leading-only hyphen is a negative
            // single residue ("-5"), not a range.
            if value.dropFirst().contains("-") {
                return SelectionAST(kind: .residueRange, left: nil, right: nil, operand: nil, value: value)
            } else {
                return SelectionAST(kind: .residue, left: nil, right: nil, operand: nil, value: value)
            }
        } else if token == "resn" {
            index += 1
            guard index < tokens.count else { throw ParserError.missingValue("resn") }
            let value = tokens[index].uppercased()
            index += 1
            return SelectionAST(kind: .residueName, left: nil, right: nil, operand: nil, value: value)
        } else if token == "model" {
            index += 1
            guard index < tokens.count else { throw ParserError.missingValue("model") }
            let value = tokens[index]
            index += 1
            return SelectionAST(kind: .model, left: nil, right: nil, operand: nil, value: value)
        }

        throw ParserError.unexpectedToken(token)
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

        var errorDescription: String? {
            switch self {
            case .unexpectedToken(let t): "Unexpected token: \(t)"
            case .unexpectedEOF: "Unexpected end of expression"
            case .missingClosingParen: "Missing closing parenthesis"
            case .missingValue(let t): "Missing value for \(t)"
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
