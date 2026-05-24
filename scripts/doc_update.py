#!/usr/bin/env python3
"""
doc_update.py — AI-powered documentation updater.

Usage:
    python doc_update.py README.md CLAUDE.md

For each doc file, checks whether recent code changes (HEAD^..HEAD) warrant
an update and writes the updated content in-place. Exits 0 with no changes if
no updates are needed.

Required env:
    ANTHROPIC_API_KEY

Optional env:
    DOC_UPDATE_MODEL  (default: claude-sonnet-4-6)
    CODE_DIFF_DEPTH   (default: 1 — compares HEAD^ to HEAD)
"""

import os
import subprocess
import sys

import anthropic


def run(cmd: list[str], *, check: bool = True) -> str:
    result = subprocess.run(cmd, capture_output=True, text=True, check=check)
    return result.stdout.strip()


def code_diff(depth: int = 1) -> str:
    """Return a diff of non-doc code changes from the last N commits."""
    base = f"HEAD~{depth}"
    diff = run(
        [
            "git",
            "diff",
            base,
            "HEAD",
            "--",
            ".",
            ":(exclude)*.md",
            ":(exclude)*.rst",
            ":(exclude)docs/",
            ":(exclude)CHANGELOG*",
            ":(exclude)CHANGES*",
        ],
        check=False,
    )
    return diff


def doc_git_log(path: str, n: int = 10) -> str:
    """Return the last N commit messages that touched this doc file."""
    return run(
        ["git", "log", "--oneline", f"-{n}", "--", path],
        check=False,
    )


def read_file(path: str) -> str:
    with open(path) as f:
        return f.read()


def write_file(path: str, content: str) -> None:
    with open(path, "w") as f:
        f.write(content)


SYSTEM_PROMPT = """\
You are a technical documentation maintainer. Your job is to keep project \
documentation accurate and up-to-date when source code changes.

Rules:
- Preserve the existing writing style, tone, and structure of the document.
- Only update content that is factually affected by the code diff.
- Do not rewrite or improve sections that are still accurate.
- Do not add new sections unless the diff introduces a genuinely new concept \
  that is missing from the docs.
- If the diff does not affect any content in the document, reply with exactly \
  the string: NO_UPDATE_NEEDED
- Otherwise, reply with the complete updated document content and nothing else \
  (no code fences, no explanation, no preamble).\
"""


def update_doc(client: anthropic.Anthropic, diff: str, doc_path: str, model: str) -> str | None:
    """
    Returns the updated doc content, or None if no update is needed.
    """
    current_content = read_file(doc_path)
    git_log = doc_git_log(doc_path)

    if not diff:
        return None

    messages = [
        {
            "role": "user",
            "content": [
                {
                    "type": "text",
                    "text": f"## Code changes (git diff)\n\n```diff\n{diff}\n```",
                },
                {
                    "type": "text",
                    "text": (
                        f"## Recent commit history for {doc_path}\n\n"
                        f"(Use this to understand the documentation update style and cadence)\n\n"
                        f"```\n{git_log or '(no history)'}\n```"
                    ),
                },
                {
                    "type": "text",
                    "text": f"## Current content of {doc_path}\n\n{current_content}",
                    "cache_control": {"type": "ephemeral"},
                },
                {
                    "type": "text",
                    "text": (
                        f"Given the code changes above, does `{doc_path}` need to be updated? "
                        "If yes, return the complete updated file. "
                        "If no, reply with exactly: NO_UPDATE_NEEDED"
                    ),
                },
            ],
        }
    ]

    response = client.messages.create(
        model=model,
        max_tokens=8192,
        system=SYSTEM_PROMPT,
        messages=messages,
        betas=["prompt-caching-2024-07-31"],
    )

    text = response.content[0].text.strip()
    if text == "NO_UPDATE_NEEDED":
        return None
    return text


def main() -> None:
    doc_paths = sys.argv[1:]
    if not doc_paths:
        print("Usage: doc_update.py <doc1> [doc2 ...]", file=sys.stderr)
        sys.exit(1)

    missing = [p for p in doc_paths if not os.path.exists(p)]
    if missing:
        print(f"Error: files not found: {', '.join(missing)}", file=sys.stderr)
        sys.exit(1)

    model = os.environ.get("DOC_UPDATE_MODEL", "claude-sonnet-4-6")
    depth = int(os.environ.get("CODE_DIFF_DEPTH", "1"))

    client = anthropic.Anthropic()

    diff = code_diff(depth)
    if not diff:
        print("No code changes detected — skipping doc update.")
        sys.exit(0)

    updated_any = False
    for path in doc_paths:
        print(f"Checking {path}...", flush=True)
        updated = update_doc(client, diff, path, model)
        if updated is None:
            print(f"  {path}: no update needed")
        else:
            write_file(path, updated)
            print(f"  {path}: updated")
            updated_any = True

    # Exit code 2 signals to the workflow that files were changed
    sys.exit(2 if updated_any else 0)


if __name__ == "__main__":
    main()
