#!/usr/bin/env python3
"""Check recursive bilingual guides and local links without network access."""

import re
import subprocess
import sys
from pathlib import Path
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parent.parent
GITHUB_ROOT = "https://github.com/chenyuhao0628/displayweave/blob/main/"


def markdown_links(text):
    text = re.sub(r"(?ms)^\s*(```|~~~).*?^\s*\1[^\n]*$", "", text)
    # Examples in inline code are literal text, not navigable links.
    text = re.sub(r"(`+)(?!`)(.+?)\1(?!`)", "", text)
    inline = re.findall(r"!?\[[^\]\n]*\]\(<?([^\s)>]+)>?(?:\s+[^)]+)?\)", text)
    references = re.findall(r"(?m)^\s*\[[^\]\n]+\]:\s*<?([^\s>]+)", text)
    return inline + references


def local_target(root, path, link):
    if link.startswith(GITHUB_ROOT):
        return root / unquote(urlsplit(link[len(GITHUB_ROOT):]).path)
    parts = urlsplit(link)
    if parts.scheme or parts.netloc or not parts.path:
        return None
    return (path.parent / unquote(parts.path)).resolve()


def check(root, files):
    failures = []
    pairs = 0
    markdown = [p for p in files if p.suffix == ".md"]
    for path in markdown:
        text = path.read_text()
        links = markdown_links(text)
        name = path.relative_to(root).as_posix()
        if path.name.endswith(".zh-CN.md"):
            english = path.with_name(path.name.replace(".zh-CN.md", ".md"))
            if not english.is_file():
                failures.append(f"{name}: missing English peer")
        else:
            chinese = path.with_name(path.stem + ".zh-CN.md")
            required = name.startswith("docs/") and not name.startswith("docs/archive/")
            required |= name in {"README.md", "CONTRIBUTING.md", "ARCHITECTURE.md", "ROADMAP.md", "SECURITY.md", "SUPPORT.md", "AndroidReceiver/README.md"}
            if required and not chinese.is_file():
                failures.append(f"{name}: missing Chinese peer")
            if chinese.is_file():
                pairs += 1
                for source, target in [(path, chinese), (chinese, path)]:
                    destinations = [local_target(root, source, url) for url in markdown_links(source.read_text())]
                    if target.resolve() not in destinations:
                        failures.append(f"{source.relative_to(root)}: missing reciprocal link to {target.name}")
        for link in links:
            target = local_target(root, path, link)
            if target is not None and not target.exists():
                failures.append(f"{name}: broken link {link}")
    # Include current GitHub doc links in website templates; expand the bilingual suffix.
    for path in files:
        if path.suffix not in {".tsx", ".ts", ".html"}:
            continue
        for suffix in ("", ".zh-CN"):
            text = re.sub(r'\$\{[^}]+\?\s*"\.zh-CN"\s*:\s*""\}', suffix, path.read_text())
            for link in re.findall(re.escape(GITHUB_ROOT) + r'[^\s"`<>]+', text):
                target = local_target(root, path, link)
                if not target.is_file():
                    failures.append(f"{path.relative_to(root)}: broken GitHub main link {link}")
    return pairs, failures


def main():
    names = subprocess.check_output(["git", "-C", str(ROOT), "ls-files", "--cached", "--others", "--exclude-standard", "-z"], text=True).split("\0")
    files = sorted({ROOT / name for name in names if name and (ROOT / name).is_file()})
    pairs, failures = check(ROOT, files)
    if failures:
        print("\n".join(failures), file=sys.stderr)
        sys.exit(1)
    print(f"Documentation check PASS: {pairs} bilingual pairs; Markdown and website documentation links resolve")


if __name__ == "__main__":
    main()
