#!/usr/bin/env python3
"""Extract lab assets from theory.md into per-lab directories.

theory.md is READ ONLY. This script never writes to it.
Re-run after editing theory.md to regenerate the lab kits.
"""
import os, re, sys, json, shutil

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(os.path.dirname(ROOT), "theory.md")
OUT = os.path.join(ROOT, "ansible", "roles", "labkit", "files")

LAB_HEADING = re.compile(r'^(#{2,3}) Lab (\d+)(?: ·)? — (.+)$')
SAVE_AS = re.compile(r'\*\*Save as \*\*\*\*`([^`]+)`\*\*\*\*:\*\*')


def parse_blocks(md):
    """Yield (kind, payload) in document order.

    kind is 'heading' (level, text), 'saveas' (filename), 'code' (lang, body)
    or 'text' (line).
    """
    lines = md.split("\n")
    i = 0
    while i < len(lines):
        line = lines[i]
        if line.startswith("```"):
            lang = line[3:].strip()
            body = []
            i += 1
            while i < len(lines) and not lines[i].startswith("```"):
                body.append(lines[i])
                i += 1
            yield ("code", (lang, "\n".join(body)))
        else:
            m = re.match(r'^(#{1,6}) (.+)$', line)
            if m:
                yield ("heading", (len(m.group(1)), m.group(2).strip()))
            else:
                sa = SAVE_AS.search(line)
                if sa:
                    yield ("saveas", sa.group(1))
                else:
                    yield ("text", line)
        i += 1


def main():
    md = open(SRC, encoding="utf-8").read()
    if os.path.isdir(OUT):
        shutil.rmtree(OUT)
    os.makedirs(OUT, exist_ok=True)

    labs = {}
    current = None
    pending_name = None

    for kind, payload in parse_blocks(md):
        if kind == "heading":
            level, text = payload
            m = LAB_HEADING.match("#" * level + " " + text)
            if m:
                num = int(m.group(2))
                current = num
                labs[num] = {
                    "number": num,
                    "title": m.group(3).strip(),
                    "level": level,
                    "files": {},
                    "steps": [],
                    "lines": [],
                }
                pending_name = None
                continue
            if current is not None and level <= labs[current]["level"]:
                current = None
                pending_name = None
            if current is not None:
                labs[current]["lines"].append("#" * level + " " + text)
            continue

        if current is None:
            continue
        lab = labs[current]

        if kind == "saveas":
            pending_name = payload
            lab["lines"].append(f"Save as `{payload}`:")
        elif kind == "text":
            lab["lines"].append(payload)
        elif kind == "code":
            lang, body = payload
            lab["lines"].append(f"```{lang}\n{body}\n```")
            if lang in ("yaml", "docker") and pending_name:
                lab["files"][pending_name] = body + "\n"
                pending_name = None
            elif lang == "bash":
                lab["steps"].append(body + "\n")
            elif lang == "yaml" and not pending_name:
                lab["files"][f"unnamed-{len(lab['files']):02d}.yaml"] = body + "\n"

    index = []
    for num in sorted(labs):
        lab = labs[num]
        d = os.path.join(OUT, f"lab{num:02d}")
        os.makedirs(d, exist_ok=True)
        for name, body in lab["files"].items():
            with open(os.path.join(d, name), "w", encoding="utf-8") as fh:
                fh.write(body)
        with open(os.path.join(d, "LAB.md"), "w", encoding="utf-8") as fh:
            fh.write(f"# Lab {num} — {lab['title']}\n\n")
            fh.write("Extracted verbatim from theory.md. Do not edit here; edit theory.md\n"
                     "and re-run bin/extract-labs.py.\n\n")
            fh.write("\n".join(lab["lines"]).strip() + "\n")
        for n, step in enumerate(lab["steps"], 1):
            with open(os.path.join(d, f"step{n:02d}.sh"), "w", encoding="utf-8") as fh:
                fh.write("#!/usr/bin/env bash\n# Extracted from theory.md — Lab "
                         f"{num}, command block {n}.\n# Read before running; some blocks "
                         "expect variables set by earlier blocks.\n\n" + step)
            os.chmod(os.path.join(d, f"step{n:02d}.sh"), 0o755)
        index.append({
            "number": num,
            "title": lab["title"],
            "manifests": sorted(lab["files"]),
            "steps": len(lab["steps"]),
        })
        print(f"lab{num:02d}  {len(lab['files'])} manifest(s), {len(lab['steps'])} command block(s)  — {lab['title']}")

    with open(os.path.join(OUT, "index.json"), "w", encoding="utf-8") as fh:
        json.dump(index, fh, indent=2)
        fh.write("\n")
    print(f"\nwrote {len(index)} lab kits to {OUT}")


if __name__ == "__main__":
    sys.exit(main())
