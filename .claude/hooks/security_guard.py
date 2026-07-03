#!/usr/bin/env python3
"""
PreToolUse security guard hook.

Denies:
  - Reading or writing real .env files (but not .env.example, .env.template, etc.)
  - Recursive deletes (rm -r/-rf/-fr, rmdir, find -delete, git clean -d)
  - Untrusted opaque code execution — code that isn't literal in the command, so no
    human sees what will run when it is authored: pipe-to-shell (curl … | sh, wget …
    | bash, bare … | sh) and command substitution (sh -c "$(…)" / backtick / eval).
    Network fetch is only one source; bare command substitution (e.g.
    eval "$(ssh-agent)") is denied too — see ADR-0019.
  - Dangerous git push — force-push (--force / -f / +refspec, but NOT the safe lease
    family --force-with-lease / --force-if-includes to a non-default branch) and
    push-to-default-branch (main/master). This is the deterministic floor ADR-0020
    mandates: it holds in EVERY permission mode, independent of the permission layer
    (the auto-mode classifier was probe-shown to approve both forms). The benign
    git push stays merely on the `ask` checkpoint; only these two forms are denied.

    Known string-layer limits (out of scope BY DESIGN — a string matcher cannot see a
    value that is not literal in the command, the same class CONTEXT.md names *opaque
    code execution*; all three are backstopped by the standing `git push: ask`
    checkpoint, ADR-0020):
      - the implicit bare `git push` (upstream target is not in the string);
      - quoted or variable-expanded branch/flag tokens (git push origin "main",
        'main', $BR, line-split forms) — deliberately NOT chased with more patterns;
      - main/master are matched by convention, not by querying the repo's real default.
    What the floor DOES cover (and must): global-option prefixes the agent emits
    naturally (git -C <path> push …, git -c k=v push …, git --no-pager push …) — only
    global-option tokens are allowed between `git` and the `push` subcommand, so these
    do not slip, while an intervening subcommand word (git commit … push …) breaks the
    match. The check inspects ONLY the push command's own argument tokens, bounded at
    the next shell operator / newline / redirection — never the surrounding command
    text. So a commit message, PR body, or branch name that merely contains the words
    "push" and "main" (e.g. a commit titled "scope push to main", or pushing the branch
    `chore/ci-scope-push-to-main`) is not a false match — the class that motivated this
    precision after it blocked benign work.

Denials exit(2) with the reason on stderr. Per ADR-0016, only an exit(2) block is
evaluated before the deny→ask→allow rule flow, so it overrides a matching allow rule
instead of being silently ignored (an exit(0)+JSON deny would lose to a broad allowlist).

Fails open (exit 0) on parse errors so it never blocks non-Bash/file tools unexpectedly.
"""

import json
import re
import sys


def check_env_file(tool_name: str, tool_input: dict) -> str | None:
    """Return a denial reason if a real .env file is being accessed, else None."""
    file_keys = []
    if tool_name in ("Read", "Edit", "MultiEdit", "Write"):
        file_keys = ["file_path"]
    elif tool_name == "Glob":
        file_keys = ["pattern"]
    elif tool_name == "Grep":
        file_keys = ["include"]

    for key in file_keys:
        path = tool_input.get(key, "")
        if not isinstance(path, str):
            continue
        filename = path.split("/")[-1]
        # Match .env exactly, or .env followed by a non-alphanumeric non-dot char
        # This allows .env.example, .env.local.example but blocks .env, .env.local, .env.production
        if re.match(r"^\.env$", filename):
            return f"Blocked: reading/writing real .env file '{path}'"
        # Block .env.<word> but not .env.example or .env.template or .env.sample
        if re.match(r"^\.env\.[^.]+$", filename):
            safe_suffixes = {"example", "template", "sample", "test"}
            suffix = filename.split(".", 2)[-1].lower()
            if suffix not in safe_suffixes:
                return f"Blocked: reading/writing real .env file '{path}'"

    return None


RECURSIVE_DELETE_PATTERNS = [
    r"\brm\s+(-\S*[rR]\S*|-\S*[fF]\S*[rR]\S*)\s",   # rm -r, rm -rf, rm -fr, rm -Rf, etc.
    r"\brmdir\b.*-[a-zA-Z]*p",                         # rmdir -p removes the ancestor chain
    r"\bfind\b.*\s--?delete\b",                        # find -delete / find --delete
    r"\bgit\s+clean\b.*\s-[a-zA-Z]*d",                 # git clean -d, git clean -fd, etc.
]


def check_recursive_delete(tool_name: str, tool_input: dict) -> str | None:
    """Return a denial reason if a recursive delete is detected, else None."""
    if tool_name != "Bash":
        return None
    command = tool_input.get("command", "")
    if not isinstance(command, str):
        return None
    for pattern in RECURSIVE_DELETE_PATTERNS:
        if re.search(pattern, command):
            return (
                f"Blocked: recursive delete detected in command: {command!r}. "
                "Run recursive deletes manually (e.g. `! rm -rf …`) so a human is in the loop."
            )
    return None


OPAQUE_EXEC_PATTERNS = [
    r"\|\s*(sudo\s+)?(sh|bash|zsh)\b",          # … | sh, curl … | sudo bash, wget … | bash (\b avoids | shasum)
    r"\b(sh|bash|zsh)\s+-c\b.*(\$\(|`)",        # sh -c "$(…)" / bash -c `…` command-substitution exec
    r"\beval\b.*(\$\(|`)",                       # eval "$(…)" / eval `…`
]


def check_opaque_exec(tool_name: str, tool_input: dict) -> str | None:
    """Return a denial reason if untrusted opaque code execution is detected, else None."""
    if tool_name != "Bash":
        return None
    command = tool_input.get("command", "")
    if not isinstance(command, str):
        return None
    for pattern in OPAQUE_EXEC_PATTERNS:
        if re.search(pattern, command):
            return (
                f"Blocked: untrusted opaque code execution detected in command: {command!r}. "
                "If this is a code SEARCH (grep/rg/sed/awk) and the exec-looking bytes the guard "
                "matched (`| sh`/`| bash`/`| zsh`, or `$(`/backtick next to `eval` or `sh -c`) "
                "actually sit inside your quoted regex rather than being executed, this is a "
                "FALSE match — the guard string-matches the whole command, quoted literals "
                "included, so it can't tell an executed `| bash` from those bytes inside a "
                "regex. Re-run the search with the Grep tool, which this Bash-only check never "
                "inspects. For a pipeline you actually intend, run it manually (e.g. `! …`)."
            )
    return None


# Match a REAL `git push` and inspect ONLY that push's own arguments — never the
# surrounding command text. Two precision rules kill the false-positive class where the
# words "push" and "main" merely co-occur (a commit message, PR body, or branch name):
#
#   _GIT_OPTS — between `git` and the `push` subcommand, allow ONLY global-option
#   tokens, never an intervening bareword. So `git commit -m "scope push to main"` does
#   not anchor (the bareword `commit` breaks the run), and a `push` sitting inside a
#   message/heredoc has no `git`(+options) directly before it. Options that take a
#   separate-token value are enumerated so the value is consumed, not read as the
#   subcommand — preserving the forms the floor MUST cover (git -C <path> push …,
#   git -c k=v push …, git --no-pager push …).
#
#   _PUSH_ARGS — after `push`, scan only this command's own argument tokens: stop at a
#   shell operator (| ; &), a newline, or a redirection (< >). Without the bound the
#   scan ran past the push into a following command or trailing prose and matched a
#   `main` the push never targeted.
#
# Policy is unchanged (ADR-0020): deny force-push and push-to-default-branch only. The
# documented string-layer limits above still apply, backstopped by `git push: ask`.
_GIT_OPTS = (
    r"(?:\s+(?:"
    r"(?:-C|-c|--git-dir|--work-tree|--namespace|--exec-path|--super-prefix|--config-env)(?:=\S+|\s+\S+)"
    r"|--[\w-]+(?:=\S+)?"
    r"|-[A-Za-z]+"
    r"))*"
)
_PUSH = r"\bgit\b" + _GIT_OPTS + r"\s+push\b"   # git, only global options, then the push subcommand
_PUSH_ARGS = r"[^|;&\n<>]*"                       # this push's own args; never crosses into another command

DANGEROUS_PUSH_PATTERNS = [
    # Force-push: --force (but NOT --force-with-lease / --force-if-includes, both the
    # safe lease-family flags allowed per policy — negative lookahead)
    (_PUSH + _PUSH_ARGS + r"\s--force(?!-with-lease|-if-includes)\b", "force-push (--force)"),
    # Force-push: -f, incl. clustered short flags (-fu)
    (_PUSH + _PUSH_ARGS + r"\s-[a-zA-Z]*f", "force-push (-f)"),
    # Force-push via +-prefixed refspec: git push origin +main / +HEAD:main / +feature
    (_PUSH + _PUSH_ARGS + r"\s\+\S", "force-push (+refspec)"),
    # Push to default branch — destination side of a refspec is main/master (HEAD:main, feature:main)
    (_PUSH + _PUSH_ARGS + r":(\+)?(refs/heads/)?(main|master)\b", "push to default branch (refspec dest)"),
    # Push to default branch — bare branch arg main/master (not the source side of a src:dst refspec)
    (_PUSH + _PUSH_ARGS + r"\s(\+)?(refs/heads/)?(main|master)(\s|$)", "push to default branch"),
]


def check_dangerous_push(tool_name: str, tool_input: dict) -> str | None:
    """Return a denial reason if a dangerous git push is detected, else None.

    Floor for force-push and push-to-default-branch (ADR-0020); see module docstring
    "Known string-layer limits" for what it deliberately cannot catch.
    """
    if tool_name != "Bash":
        return None
    command = tool_input.get("command", "")
    if not isinstance(command, str):
        return None
    for pattern, label in DANGEROUS_PUSH_PATTERNS:
        if re.search(pattern, command):
            return (
                f"Blocked: dangerous git push ({label}) in command: {command!r}. "
                "Force-push and push-to-default-branch are denied in every mode (ADR-0020). "
                "Run it manually (e.g. `! git push …`) if you intend it."
            )
    return None


def main() -> None:
    try:
        data: dict = json.load(sys.stdin)
    except Exception as e:
        print(f"[security-guard] Could not parse hook JSON: {e}", file=sys.stderr)
        sys.exit(0)  # fail open

    tool_name = data.get("tool_name", "")
    tool_input = data.get("tool_input", {})

    reason = (
        check_env_file(tool_name, tool_input)
        or check_recursive_delete(tool_name, tool_input)
        or check_opaque_exec(tool_name, tool_input)
        or check_dangerous_push(tool_name, tool_input)
    )

    if reason:
        print(reason, file=sys.stderr)
        sys.exit(2)

    sys.exit(0)


if __name__ == "__main__":
    main()
