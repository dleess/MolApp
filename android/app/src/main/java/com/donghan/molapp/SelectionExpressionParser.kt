package com.donghan.molapp

/**
 * Recursive-descent parser for the selection mini-language (chain/res/resn/atom/model with
 * &, |, !, parens). Direct port of the iOS SelectionExpressionParser so both platforms emit the
 * identical AST the viewer's queryFromAST consumes.
 */
class SelectionExpressionParser(expression: String) {
    private val tokens: List<String>
    private var index = 0

    init {
        var expr = expression
        for (s in symbols) expr = expr.replace(s, " $s ")
        tokens = expr.split(Regex("\\s+")).filter { it.isNotEmpty() }
    }

    class ParseException(message: String) : Exception(message)

    fun parse(): SelAst {
        val ast = parseOr()
        if (index < tokens.size) throw ParseException("Unexpected token: ${tokens[index]}")
        return ast
    }

    private fun parseOr(): SelAst {
        var node = parseAnd()
        while (index < tokens.size && (tokens[index] == "|" || tokens[index].lowercase() == "or")) {
            index++
            node = SelAst(kind = "or", left = node, right = parseAnd())
        }
        return node
    }

    private fun parseAnd(): SelAst {
        var node = parseNot()
        while (index < tokens.size && (tokens[index] == "&" || tokens[index].lowercase() == "and")) {
            index++
            node = SelAst(kind = "and", left = node, right = parseNot())
        }
        return node
    }

    private fun parseNot(): SelAst {
        if (index < tokens.size && (tokens[index] == "!" || tokens[index].lowercase() == "not")) {
            index++
            return SelAst(kind = "not", operand = parseNot())
        }
        return parsePrimary()
    }

    private fun parsePrimary(): SelAst {
        if (index >= tokens.size) throw ParseException("Unexpected end of expression")

        val raw = tokens[index]
        val token = raw.lowercase()
        if (token == "(") {
            index++
            val node = parseOr()
            if (index >= tokens.size || tokens[index] != ")") throw ParseException("Missing closing parenthesis")
            index++
            return node
        }

        when (token) {
            "chain" -> {
                index++
                if (index >= tokens.size) throw ParseException("Missing value for chain")
                // Preserve case: chain IDs are case-sensitive.
                val value = tokens[index]; index++
                return SelAst(kind = "chain", value = value)
            }
            "atom" -> {
                index++
                if (index >= tokens.size) throw ParseException("Missing value for atom")
                val value = tokens[index].uppercase(); index++
                return SelAst(kind = "atom", value = value)
            }
            "res", "residue" -> {
                index++
                if (index >= tokens.size) throw ParseException("Missing value for $token")
                val value = tokens[index]; index++
                // A range needs an interior hyphen ("3-42"); a leading-only hyphen is a negative
                // single residue ("-5"), not a range.
                return if (value.drop(1).contains("-")) {
                    SelAst(kind = "residueRange", value = value)
                } else {
                    SelAst(kind = "residue", value = value)
                }
            }
            "resn" -> {
                index++
                if (index >= tokens.size) throw ParseException("Missing value for resn")
                val value = tokens[index].uppercase(); index++
                return SelAst(kind = "residueName", value = value)
            }
            "model" -> {
                index++
                if (index >= tokens.size) throw ParseException("Missing value for model")
                val value = tokens[index]; index++
                return SelAst(kind = "model", value = value)
            }
        }

        throw ParseException("Unexpected token: $token")
    }

    companion object {
        val symbols = listOf("&", "|", "!", "(", ")")
        private val keywords = setOf("chain", "residue", "res", "resn", "atom", "model", "not", "and", "or")

        /** Splits "name expr..." into (name, expression); defaults name to "sele". */
        fun extractName(afterSelect: String): Pair<String, String> {
            val parts = afterSelect.split(Regex("\\s+")).filter { it.isNotEmpty() }
            val symbolChars = symbols.joinToString("").toSet()
            if (parts.size >= 2 && !keywords.contains(parts[0].lowercase()) &&
                parts[0].none { symbolChars.contains(it) }
            ) {
                return parts[0] to parts.drop(1).joinToString(" ")
            }
            return "sele" to afterSelect
        }
    }
}
