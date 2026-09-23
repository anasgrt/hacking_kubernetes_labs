#!/usr/bin/env python3
"""The question and solution cards, and the YAML subset parser behind them.

The parser exists because no stock macOS Python has PyYAML. That is a real
risk: a hand-rolled parser can mis-read a file instead of failing on it, and
the result would be a card that renders with a question quietly missing. These
tests pin the grammar it accepts and check it rejects everything else.
"""
import importlib.util
import pathlib
import subprocess
import sys
from importlib.machinery import SourceFileLoader

ROOT = pathlib.Path(__file__).resolve().parents[1]
loader = SourceFileLoader("hk_card", str(ROOT / "bin/hk-card"))
spec = importlib.util.spec_from_loader("hk_card", loader)
card = importlib.util.module_from_spec(spec)
loader.exec_module(card)

PASSED = FAILED = 0


def check(name, got, want):
    global PASSED, FAILED
    if got == want:
        PASSED += 1
        print(f"  \033[32mok\033[0m    {name}")
    else:
        FAILED += 1
        print(f"  \033[31mFAIL\033[0m  {name}\n          got:  {got!r}\n          want: {want!r}")


def rejects(name, text):
    global PASSED, FAILED
    try:
        card.parse_card(text)
    except ValueError:
        PASSED += 1
        print(f"  \033[32mok\033[0m    {name}")
        return
    FAILED += 1
    print(f"  \033[31mFAIL\033[0m  {name} — parsed instead of raising")


print("the YAML subset parser")
check("plain scalar", card.parse_card("title: Lab 4 — x")["title"], "Lab 4 — x")
check("folded scalar joins lines with spaces",
      card.parse_card("objective: >-\n  one\n  two\n")["objective"], "one two")
check("list of folded items",
      card.parse_card("theory:\n  - >-\n    a\n    b\n  - >-\n    c\n")["theory"],
      ["a b", "c"])
check("list of plain items",
      card.parse_card("theory:\n  - a\n  - b\n")["theory"], ["a", "b"])
check("comments and blank lines ignored",
      card.parse_card("# c\n\ntitle: x\n")["title"], "x")
check("a later key ends the previous block",
      card.parse_card("objective: >-\n  a\nrelated: b\n"),
      {"objective": "a", "related": "b"})
check("quotes stripped from a plain scalar",
      card.parse_card('title: "x"')["title"], "x")
rejects("a line that is not a key", "not a key at all\n")
rejects("indented text with no owning key", "  orphan\n")
rejects("a list item outside a list", "title: x\n  - stray\n")

# Regression: a folded item wrapping onto a line that starts with '-' (a long
# flag such as --local) was read as a new list entry, splitting one question
# into two. It passed the count check because the matching answer split the
# same way, so only an indentation-aware parser catches it.
check("a wrapped line starting with a dash stays in its item",
      card.parse_card("answer_with:\n  - >-\n    run k patch\n    --local now\n")["answer_with"],
      ["run k patch --local now"])
check("a real second entry at the dash column is still a new item",
      card.parse_card("theory:\n  - >-\n    a\n    --flag\n  - >-\n    b\n")["theory"],
      ["a --flag", "b"])
check("lab09 asks four questions, not five",
      len(card.parse_card((ROOT / "questions/lab09.yml").read_text())["answer_with"]), 4)

print("every card is well formed")
cards = sorted((ROOT / "questions").glob("lab*.yml"))
check("one card per lab", len(cards), 11)
for f in cards:
    d = card.parse_card(f.read_text(), str(f))
    missing = (card.SCALARS - {"notes"} | card.LISTS) - set(d)
    check(f"{f.stem} has every required field", missing, set())
    check(f"{f.stem} answers every question it asks",
          len(d["answer_with"]), len(d["solution"]))
    check(f"{f.stem} asks at least three questions", len(d["answer_with"]) >= 3, True)
    # A folded block that swallowed the next key would show up as a stray
    # 'key:' inside prose, which is exactly the silent mis-parse to catch.
    strays = [k for k in (card.SCALARS | card.LISTS)
              if any(f"{k}:" in v for v in
                     [d.get(s, "") for s in card.SCALARS] +
                     [x for l in card.LISTS for x in d.get(l, [])])]
    check(f"{f.stem} has no field swallowed into prose", strays, [])

print("the commands come from theory.md, not from the cards")
for n in range(11):
    steps = card.lab_steps(n)
    files = sorted((ROOT / "ansible/roles/labkit/files" / f"lab{n:02d}").glob("step*.sh"))
    # If these ever diverge, "STEP 3 OF 5" in a card points at a different
    # command than step03.sh in the VM — the worst kind of wrong, because both
    # look right on their own.
    check(f"lab{n:02d} step count matches stepNN.sh", len(steps), len(files))
    for i, (_, cmds, _) in enumerate(steps):
        body = files[i].read_text().split("\n\n", 1)[-1].strip()
        check(f"lab{n:02d} step {i+1} is the same command as {files[i].name}",
              cmds.strip(), body)
check("expected results carry no markdown links",
      any("](" in (e or "") for n in range(11) for _, _, e in card.lab_steps(n)), False)

print("both cards render for every lab")
for n in range(11):
    for action in ("question", "solution"):
        r = subprocess.run([str(ROOT / "bin/hk-card"), action, str(n)],
                           capture_output=True, text=True)
        ok = r.returncode == 0 and len(r.stdout) > 400
        check(f"lab{n:02d} {action} renders", ok, True)

print("a solution card actually contains the answers")
q = subprocess.run([str(ROOT / "bin/hk-card"), "question", "4"],
                   capture_output=True, text=True).stdout
s = subprocess.run([str(ROOT / "bin/hk-card"), "solution", "4"],
                   capture_output=True, text=True).stdout
# The lesson is deliberately stated up front: knowing what the lab is for is
# what lets you tell a real result from a lucky one. It is the answers that
# are withheld, not the point of the exercise.
check("question card states the main lesson", "MAIN LESSON TO LEARN" in q, True)
check("main lesson comes after the theory, before the questions",
      q.index("THEORY YOU NEED") < q.index("MAIN LESSON TO LEARN") < q.index("QUESTIONS TO ANSWER"),
      True)
check("question card still withholds the answers", "QUESTION 1\n----------" in q, False)
check("solution card states the main lesson", "MAIN LESSON" in s, True)
check("question card lists the questions", "QUESTIONS TO ANSWER" in q, True)
check("question card gives the commands", "THE LAB'S OWN STEPS" in q, True)
check("question card withholds expected results", "Expected:" in q, False)
check("solution card gives the commands", "Step 3 of 5" in s, True)
check("solution card states expected results", "Expected:" in s, True)

print("every answer is mapped to the steps that evidence it")
for n in range(11):
    d = card.parse_card((ROOT / "questions" / f"lab{n:02d}.yml").read_text())
    steps = card.lab_steps(n)
    m = d.get("solution_steps", [])
    check(f"lab{n:02d} maps one entry per question", len(m), len(d["answer_with"]))
    for i, entry in enumerate(m, 1):
        refs = [r for r in str(entry).split() if r != "-"]
        bad = [r for r in refs if not r.isdigit() or not 1 <= int(r) <= len(steps)]
        check(f"lab{n:02d} answer {i} names real steps", bad, [])
    # A mapping of all dashes would render a solution with no commands at all,
    # which is the thing this feature exists to prevent.
    check(f"lab{n:02d} shows a command for at least one answer",
          any(r.isdigit() for e in m for r in str(e).split()), True)

# The commands must sit under their own answer, not in a block at the end.
sol = subprocess.run([str(ROOT / "bin/hk-card"), "solution", "4"],
                     capture_output=True, text=True).stdout
q3 = sol.index("QUESTION 3")
q4 = sol.index("QUESTION 4")
check("a question's commands appear between it and the next question",
      "Step 3 of 5" in sol[q3:q4], True)
check("no trailing bundle of all the commands",
      "COMMANDS THAT PRODUCE THESE ANSWERS" in sol, False)

print("the parser strips quotes from list items too")
check("quoted list entry", card.parse_card("solution_steps:\n  - '2 3'\n")["solution_steps"], ["2 3"])
check("double-quoted list entry", card.parse_card('theory:\n  - "x"\n')["theory"], ["x"])

print("bad input is refused")
for bad in ("11", "lab11", "banana", "-1"):
    r = subprocess.run([str(ROOT / "bin/hk-card"), "question", bad],
                       capture_output=True, text=True)
    check(f"rejects {bad!r}", r.returncode != 0, True)


# --- hk-run: which steps it will and will not execute -----------------------
print("the lab runner protects what the labs create")
_rl = SourceFileLoader("hk_run", str(ROOT / "bin/hk-run"))
_rs = importlib.util.spec_from_loader("hk_run", _rl)
run = importlib.util.module_from_spec(_rs)
_rl.exec_module(run)

import re as _re
for n in range(11):
    plan = run.classify(n)
    # No step that tears the lab down may run by default. Running one would
    # leave the empty namespace the user started with — the exact complaint
    # this feature exists to answer. Lab 0 only sets things up and has no
    # teardown step, so it is asserted by the same rule rather than exempted.
    teardown_running = [e for e in plan
                        if _re.search(r"clean\s*up", e["heading"], _re.I) and e["skip"] is None]
    check(f"lab{n:02d} runs no teardown step", teardown_running, [])
    check(f"lab{n:02d} has at least one step that runs",
          any(e["skip"] is None for e in plan), True)
# Nine of the eleven do have a teardown step; those must be detected, not missed.
have_teardown = [n for n in range(11)
                 if any(_re.search(r"clean\s*up", e["heading"], _re.I) for e in run.classify(n))]
check("the labs with a teardown step are all found", len(have_teardown), 10)
# Labs 0 and 9 open a select menu that would hang a non-interactive run.
for n in (0, 9):
    check(f"lab{n:02d} interactive menu is skipped",
          any(e["skip"] and "interactive" in e["skip"] for e in run.classify(n)), True)
for n in (1, 4, 8):
    check(f"lab{n:02d} has no interactive step to skip",
          any(e["skip"] and "interactive" in e["skip"] for e in run.classify(n)), False)

print(f"\n{PASSED} passed, {FAILED} failed")
sys.exit(1 if FAILED else 0)
