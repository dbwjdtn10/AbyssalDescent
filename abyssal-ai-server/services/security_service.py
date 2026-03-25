"""Prompt injection detection and input sanitization service.

Filters user input to prevent prompt injection attacks while allowing
normal Korean game dialogue to pass through.
"""

from __future__ import annotations

import logging
import re
import unicodedata

logger = logging.getLogger(__name__)


class SecurityService:
    """Filters and sanitizes user input to prevent prompt injection."""

    # Blocked patterns (regex, case-insensitive)
    INJECTION_PATTERNS: list[tuple[str, str]] = [
        (r"ignore\s+(previous|above|all)\s+(instructions|prompts)", "instruction_override"),
        (r"forget\s+(everything|all|your)\s+(instructions|training|rules)", "instruction_override"),
        (r"you\s+are\s+now\s+", "role_hijack"),
        (r"act\s+as\s+(if|a)\s+", "role_hijack"),
        (r"pretend\s+(to\s+be|you\s+are)", "role_hijack"),
        (r"system\s*:\s*", "system_tag_injection"),
        (r"<\s*system\s*>", "system_tag_injection"),
        (r"\[INST\]", "format_injection"),
        (r"\[/INST\]", "format_injection"),
        (r"<<\s*SYS\s*>>", "format_injection"),
        (r"Human\s*:\s*", "format_injection"),
        (r"Assistant\s*:\s*", "format_injection"),
        (r"DAN\s+mode", "jailbreak"),
        (r"jailbreak", "jailbreak"),
        (r"override\s+(safety|filter|rules)", "safety_override"),
    ]

    # Pre-compiled patterns for performance
    _compiled_patterns: list[tuple[re.Pattern[str], str]]

    # Max message length
    MAX_MESSAGE_LENGTH = 1000

    def __init__(self) -> None:
        self._compiled_patterns = [
            (re.compile(pattern, re.IGNORECASE), violation_type)
            for pattern, violation_type in self.INJECTION_PATTERNS
        ]

    def sanitize_message(self, message: str) -> tuple[str, bool]:
        """Sanitize and validate a user message.

        Returns ``(sanitized_message, was_modified)``.
        """
        original = message
        was_modified = False

        # 1. Strip control characters (keep newlines, tabs, and standard whitespace)
        cleaned_chars: list[str] = []
        for ch in message:
            cat = unicodedata.category(ch)
            if cat == "Cc" and ch not in ("\n", "\r", "\t"):
                was_modified = True
            else:
                cleaned_chars.append(ch)
        message = "".join(cleaned_chars)

        # 2. Normalise excessive whitespace
        message = re.sub(r"[ \t]{4,}", "   ", message)
        message = message.strip()

        # 3. Truncate if too long
        if len(message) > self.MAX_MESSAGE_LENGTH:
            message = message[: self.MAX_MESSAGE_LENGTH]
            was_modified = True

        if message != original:
            was_modified = True

        return message, was_modified

    def is_safe(self, message: str) -> bool:
        """Quick check if message passes safety filters."""
        return self.get_violation_type(message) is None

    def get_violation_type(self, message: str) -> str | None:
        """Return the type of violation detected, or ``None`` if clean."""
        for compiled, violation_type in self._compiled_patterns:
            if compiled.search(message):
                logger.warning(
                    "Prompt injection detected [%s]: %.80s...",
                    violation_type,
                    message,
                )
                return violation_type
        return None


# Module-level singleton for easy imports
security_service = SecurityService()
