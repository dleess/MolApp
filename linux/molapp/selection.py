"""Recursive-descent parser for the `select` command's expression language:

    chain A & res 3-42 | !resn HOH

A direct port of `selection_expression_parser.dart` / `SelectionExpressionParser.swift` — all four
shells must stay in step because they produce the same AST for `queryFromAST` in viewer.html.
"""

from __future__ import annotations

import re

from .models import SelectionAST, SelectionASTKind

SYMBOLS = ["&", "|", "!", "(", ")"]

SELECTION_KEYWORDS = {
    "chain",
    "residue",
    "res",
    "resn",
    "atom",
    "model",
    "not",
    "and",
    "or",
}


class SelectionParseError(Exception):
    pass


class SelectionExpressionParser:
    def __init__(self, expression: str) -> None:
        self._tokens = self._tokenize(expression)
        self._index = 0

    @staticmethod
    def _tokenize(expression: str) -> list[str]:
        for symbol in SYMBOLS:
            expression = expression.replace(symbol, f" {symbol} ")
        return [token for token in re.split(r"\s+", expression) if token]

    def parse(self) -> SelectionAST:
        ast = self._parse_or()
        if self._index < len(self._tokens):
            raise SelectionParseError(f"Unexpected token: {self._tokens[self._index]}")
        return ast

    def _parse_or(self) -> SelectionAST:
        node = self._parse_and()
        while self._index < len(self._tokens) and (
            self._tokens[self._index] == "|" or self._tokens[self._index].lower() == "or"
        ):
            self._index += 1
            right = self._parse_and()
            node = SelectionAST(kind=SelectionASTKind.or_, left=[node], right=[right])
        return node

    def _parse_and(self) -> SelectionAST:
        node = self._parse_not()
        while self._index < len(self._tokens) and (
            self._tokens[self._index] == "&" or self._tokens[self._index].lower() == "and"
        ):
            self._index += 1
            right = self._parse_not()
            node = SelectionAST(kind=SelectionASTKind.and_, left=[node], right=[right])
        return node

    def _parse_not(self) -> SelectionAST:
        if self._index < len(self._tokens) and (
            self._tokens[self._index] == "!" or self._tokens[self._index].lower() == "not"
        ):
            self._index += 1
            operand = self._parse_not()
            return SelectionAST(kind=SelectionASTKind.not_, operand=[operand])
        return self._parse_primary()

    def _parse_primary(self) -> SelectionAST:
        if self._index >= len(self._tokens):
            raise SelectionParseError("Unexpected end of expression")

        raw = self._tokens[self._index]
        token = raw.lower()

        if token == "(":
            self._index += 1
            node = self._parse_or()
            if self._index >= len(self._tokens) or self._tokens[self._index] != ")":
                raise SelectionParseError("Missing closing parenthesis")
            self._index += 1
            return node

        if token == "chain":
            # Preserve case: chain IDs are case-sensitive (e.g. distinct A vs a in large assemblies).
            return SelectionAST(kind=SelectionASTKind.chain, value=self._value_for(token))
        if token == "atom":
            return SelectionAST(kind=SelectionASTKind.atom, value=self._value_for(token).upper())
        if token in ("res", "residue"):
            value = self._value_for(token)
            # A range needs an interior hyphen ("3-42"); a leading-only hyphen is a negative single
            # residue ("-5"), not a range.
            if len(value) > 1 and "-" in value[1:]:
                return SelectionAST(kind=SelectionASTKind.residueRange, value=value)
            return SelectionAST(kind=SelectionASTKind.residue, value=value)
        if token == "resn":
            return SelectionAST(
                kind=SelectionASTKind.residueName, value=self._value_for(token).upper()
            )
        if token == "model":
            return SelectionAST(kind=SelectionASTKind.model, value=self._value_for(token))

        raise SelectionParseError(f"Unexpected token: {token}")

    def _value_for(self, keyword: str) -> str:
        self._index += 1
        if self._index >= len(self._tokens):
            raise SelectionParseError(f"Missing value for {keyword}")
        value = self._tokens[self._index]
        self._index += 1
        return value

    @staticmethod
    def extract_name(after_select: str) -> tuple[str, str]:
        """Splits `select sele chain A` into the object name and the expression. A leading token
        that is not a keyword and carries no tokenizer symbol is the name; otherwise it is "sele"."""
        parts = [token for token in re.split(r"\s+", after_select) if token]
        # A name cannot contain a tokenizer symbol: the tokenizer would split it, so it was never
        # one name.
        if (
            len(parts) >= 2
            and parts[0].lower() not in SELECTION_KEYWORDS
            and not any(character in "".join(SYMBOLS) for character in parts[0])
        ):
            return parts[0], " ".join(parts[1:])
        return "sele", after_select
