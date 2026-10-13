#!/usr/bin/env python3
"""
Renders PRIVACY_POLICY.md into site/privacy.html.

The policy is maintained as Markdown because that is what gets reviewed and
diffed. Generating the page from it means the published version and the file in
the repository cannot drift apart — which matters, because App Review reads the
published one and a stale page is the kind of mismatch that gets an app held.

Run after editing the policy:   python3 site/build-privacy.py
"""

import html
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE = ROOT / "PRIVACY_POLICY.md"
# Default output. Pass a path to write somewhere else, e.g. next to the rest of
# the deployment:  python3 site/build-privacy.py server/public/privacy.html
OUTPUT = ROOT / "site" / "privacy.html"
if len(sys.argv) > 1:
    OUTPUT = pathlib.Path(sys.argv[1])
    if not OUTPUT.is_absolute():
        OUTPUT = ROOT / OUTPUT
TEMPLATE = ROOT / "site" / "_template.html"

SUPPORT_EMAIL = "support@buildinglayer.site"


def inline(text: str) -> str:
    """Escape, then apply the inline Markdown the policy actually uses."""
    out = html.escape(text, quote=False)
    out = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", out)
    out = re.sub(r"`(.+?)`", r"<code>\1</code>", out)
    # A trailing double space is a hard line break in Markdown.
    return out


def convert(markdown: str) -> tuple[str, str]:
    """Returns (body_html, last_updated)."""
    # The placeholder was never filled in; leaving it on a published page would
    # read as unfinished to a reviewer.
    markdown = markdown.replace(
        "[insert support email address]",
        f"[{SUPPORT_EMAIL}](mailto:{SUPPORT_EMAIL})",
    )

    last_updated = ""
    match = re.search(r"\*\*Last updated:\*\*\s*(.+)", markdown)
    if match:
        last_updated = match.group(1).strip()

    lines = markdown.splitlines()
    out: list[str] = []
    in_list = False
    paragraph: list[str] = []

    def flush_paragraph() -> None:
        nonlocal paragraph
        if not paragraph:
            return
        pieces = []
        for raw in paragraph:
            hard_break = raw.endswith("  ")
            pieces.append(inline(raw.strip()) + ("<br>" if hard_break else ""))
        out.append("<p>" + " ".join(pieces) + "</p>")
        paragraph = []

    def close_list() -> None:
        nonlocal in_list
        if in_list:
            out.append("</ul>")
            in_list = False

    for raw in lines:
        line = raw.rstrip("\n")
        stripped = line.strip()

        if not stripped:
            flush_paragraph()
            close_list()
            continue

        if stripped == "---":
            flush_paragraph()
            close_list()
            out.append("<hr>")
            continue

        heading = re.match(r"^(#{1,4})\s+(.*)$", stripped)
        if heading:
            flush_paragraph()
            close_list()
            level = len(heading.group(1))
            # The document's own "# Privacy Policy" becomes the page hero, so
            # everything shifts down one level to keep a single h1 on the page.
            tag = f"h{min(level + 1, 5)}"
            out.append(f"<{tag}>{inline(heading.group(2))}</{tag}>")
            continue

        bullet = re.match(r"^[-*]\s+(.*)$", stripped)
        if bullet:
            flush_paragraph()
            if not in_list:
                out.append("<ul>")
                in_list = True
            out.append(f"<li>{inline(bullet.group(1))}</li>")
            continue

        close_list()
        paragraph.append(line)

    flush_paragraph()
    close_list()

    body = "\n".join(out)
    # Markdown links, applied last so they survive escaping above.
    body = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", r'<a href="\2">\1</a>', body)
    return body, last_updated


def main() -> int:
    if not SOURCE.is_file():
        print(f"error: {SOURCE} not found", file=sys.stderr)
        return 1
    if not TEMPLATE.is_file():
        print(f"error: {TEMPLATE} not found", file=sys.stderr)
        return 1

    body, last_updated = convert(SOURCE.read_text(encoding="utf-8"))

    # The first heading and the intro block become the hero, so drop them from
    # the flowing body to avoid printing the title twice.
    body = re.sub(r"^<h2>Privacy Policy</h2>\s*", "", body)
    body = re.sub(r"^<h3>Building Layer</h3>\s*", "", body)
    body = re.sub(
        r"^<p><strong>Effective date:</strong>.*?</p>\s*", "", body, flags=re.S
    )

    page = TEMPLATE.read_text(encoding="utf-8")
    page = page.replace("{{TITLE}}", "Privacy Policy — Building Layer")
    page = page.replace(
        "{{DESCRIPTION}}",
        "How Building Layer handles your project data, photos and optional cloud backup.",
    )
    page = page.replace("{{PAGE_CLASS}}", "policy")
    page = page.replace("{{EYEBROW}}", "Legal")
    page = page.replace("{{HEADING}}", "Privacy Policy")
    page = page.replace(
        "{{LEAD}}",
        "Your project information belongs to you. This page explains exactly what "
        "Building Layer stores, what leaves your device, and how to remove it.",
    )
    page = page.replace(
        "{{META}}",
        f"Effective 4 September 2026 · Last updated {html.escape(last_updated)}",
    )
    page = page.replace("{{ACTIVE_PRIVACY}}", ' aria-current="page"')
    page = page.replace("{{ACTIVE_SUPPORT}}", "")
    page = page.replace("{{BODY}}", body)

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(page, encoding="utf-8")
    try:
        shown = OUTPUT.relative_to(ROOT)
    except ValueError:
        shown = OUTPUT
    print(f"wrote {shown}  ({len(page):,} bytes)")
    print("remember to upload it — the live page is what App Review reads")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
