#!/usr/bin/env python3
"""Install or remove the ticket feedback hook (ticket_feedback.py) in the STATBUS Jcode instance.

Usage: python3 ops/jcode/install.py [--uninstall] [--jcode-home DIR]

The STATBUS instance's home is $JCODE_HOME when set (the zsh `jcode` wrapper sets it to
/Users/jhf/ssb/.jcode for this checkout), else <checkout parent>/.jcode. Only that instance's
config.toml is changed; other Jcode instances are untouched. Existing hooks are preserved.
Running it twice is harmless. See STATBUS-510.
"""
import argparse
import os
import re
import shutil
import sys
import time
from pathlib import Path

HOOK = Path(__file__).resolve().parent / "ticket_feedback.py"
COMMAND = f"python3 {HOOK}"
TIMEOUT_MS = 45000


def toml_string(value):
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def hooks_section(text):
    match = re.search(r"(?m)^\[hooks\]\s*$", text)
    if not match:
        return None
    nxt = re.search(r"(?m)^\[", text[match.end():])
    return match.start(), match.end() + nxt.start() if nxt else len(text)


def feedback_line(section):
    return re.search(r"(?m)^post_tool_feedback\s*=\s*(.*)$", section)


def commands(value):
    value = value.strip()
    if value.startswith("["):
        return re.findall(r'"((?:[^"\\]|\\.)*)"', value)
    found = re.match(r'"((?:[^"\\]|\\.)*)"', value)
    return [found.group(1)] if found and found.group(1) else []


def install(text):
    span = hooks_section(text)
    if span is None:
        return text.rstrip("\n") + f'\n\n[hooks]\npost_tool_feedback = {toml_string(COMMAND)}\npost_tool_feedback_timeout_ms = {TIMEOUT_MS}\n'
    start, end = span
    section = text[start:end]
    line = feedback_line(section)
    if line:
        existing = commands(line.group(1))
        if COMMAND in existing:
            return text
        listed = existing + [COMMAND]
        value = toml_string(COMMAND) if len(listed) == 1 else "[" + ", ".join(map(toml_string, listed)) + "]"
        section = section[:line.start()] + f"post_tool_feedback = {value}" + section[line.end():]
    else:
        section = section.rstrip("\n") + f"\npost_tool_feedback = {toml_string(COMMAND)}\n"
    timeout = re.search(r"(?m)^post_tool_feedback_timeout_ms\s*=\s*(\d+)", section)
    if not timeout:
        section = section.rstrip("\n") + f"\npost_tool_feedback_timeout_ms = {TIMEOUT_MS}\n"
    elif int(timeout.group(1)) < TIMEOUT_MS:
        section = section[:timeout.start()] + f"post_tool_feedback_timeout_ms = {TIMEOUT_MS}" + section[timeout.end():]
    if end < len(text) and not section.endswith("\n\n"):
        section = section.rstrip("\n") + "\n\n"
    return text[:start] + section + text[end:]


def uninstall(text):
    span = hooks_section(text)
    if span is None:
        return text
    start, end = span
    section = text[start:end]
    line = feedback_line(section)
    if not line or COMMAND not in commands(line.group(1)):
        return text
    rest = [c for c in commands(line.group(1)) if c != COMMAND]
    if rest:
        value = toml_string(rest[0]) if len(rest) == 1 else "[" + ", ".join(map(toml_string, rest)) + "]"
        section = section[:line.start()] + f"post_tool_feedback = {value}" + section[line.end():]
    else:
        section = section[:line.start()] + section[line.end() + 1:]
        section = re.sub(r"(?m)^post_tool_feedback_timeout_ms\s*=.*\n", "", section)
    return text[:start] + section + text[end:]


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--uninstall", action="store_true", help="remove the hook again")
    parser.add_argument("--jcode-home", type=Path, help="Jcode instance home (default: $JCODE_HOME)")
    args = parser.parse_args()
    home = args.jcode_home or Path(os.environ.get("JCODE_HOME") or HOOK.parents[3] / ".jcode")
    config = home.expanduser().resolve() / "config.toml"
    if not config.is_file():
        sys.exit(f"No Jcode config at {config}. Pass --jcode-home for the STATBUS instance.")
    if not HOOK.is_file():
        sys.exit(f"Hook script missing: {HOOK}")
    before = config.read_text()
    after = uninstall(before) if args.uninstall else install(before)
    if after == before:
        print(f"Nothing to change in {config}.")
        return
    try:
        import tomllib
        tomllib.loads(after)
    except ImportError:
        pass
    except Exception as error:
        sys.exit(f"Refusing to write {config}: result would not parse ({error}).")
    backup = config.with_name(f"config.toml.bak-{time.strftime('%Y%m%d%H%M%S')}")
    shutil.copy2(config, backup)
    config.write_text(after)
    print(f"{'Removed' if args.uninstall else 'Installed'} the ticket feedback hook in {config} (backup: {backup.name}).")
    print("New Jcode sessions pick it up; running sessions do after a config reload.")


if __name__ == "__main__":
    main()
