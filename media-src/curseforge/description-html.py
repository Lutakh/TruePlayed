#!/usr/bin/env python3
"""Turns the CurseForge description of docs/curseforge-en.md (everything after the first
`---` line) into HTML, for CurseForge's visual (WYSIWYG) editor: paste the output in its
source-code view. Its Markdown subset: headings, paragraphs, **bold**, `code`, links,
images, numbered lists, tables, `---` rules.

    python3 media-src/curseforge/description-html.py docs/curseforge-en.md > docs/curseforge-en.html
"""
import html
import re
import sys

src = open(sys.argv[1], encoding="utf-8").read()
body = src[src.index("\n---\n") + 5:]


def inline(t):
    t = html.escape(t, quote=False)
    t = re.sub(r"!\[([^\]]*)\]\(([^)]+)\)", r'<img src="\2" alt="\1" width="800">', t)
    t = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", r'<a href="\2">\1</a>', t)
    t = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", t)
    return re.sub(r"`([^`]+)`", r"<code>\1</code>", t)


out, para, lines, i = [], [], body.split("\n"), 0


def flush():
    if para:
        text = " ".join(para)
        tag = "p" if not text.startswith("![") else "p style=\"text-align:center\""
        out.append("<%s>%s</p>" % (tag, inline(text)))
        para.clear()


while i < len(lines):
    line = lines[i]
    m = re.match(r"(#{1,6}) (.*)", line)
    if not line.strip():
        flush()
        i += 1
    elif m:
        flush()
        out.append("<h%d>%s</h%d>" % (len(m[1]), inline(m[2]), len(m[1])))
        i += 1
    elif line.strip() == "---":
        flush()
        out.append("<hr>")
        i += 1
    elif line.startswith("|"):
        flush()
        rows = []
        while i < len(lines) and lines[i].startswith("|"):
            rows.append([c.strip() for c in lines[i].strip("|").split("|")])
            i += 1
        t = "<table><thead><tr>" + "".join("<th>%s</th>" % inline(c) for c in rows[0]) + "</tr></thead><tbody>"
        for r in rows[2:]:
            t += "<tr>" + "".join("<td>%s</td>" % inline(c) for c in r) + "</tr>"
        out.append(t + "</tbody></table>")
    elif re.match(r"\d+\. ", line):
        flush()
        items = []
        while i < len(lines) and (re.match(r"\d+\. ", lines[i]) or lines[i].startswith("   ")):
            if re.match(r"\d+\. ", lines[i]):
                items.append(re.sub(r"^\d+\. ", "", lines[i]))
            else:
                items[-1] += " " + lines[i].strip()
            i += 1
        out.append("<ol>" + "".join("<li>%s</li>" % inline(x) for x in items) + "</ol>")
    else:
        para.append(line.strip())
        i += 1
flush()
print("\n".join(out))
