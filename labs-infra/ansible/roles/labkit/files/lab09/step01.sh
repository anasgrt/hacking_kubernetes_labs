#!/usr/bin/env bash
# Extracted from theory.md — Lab 9, command block 1.
# Read before running; some blocks expect variables set by earlier blocks.

k get runtimeclasses
RUNTIME_CLASSES=()
while IFS= read -r runtime_class; do
  RUNTIME_CLASSES+=("$runtime_class")
done < <(k get runtimeclasses -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')
unset LAB_RUNTIME_CLASS
PS3='Select the installed sandbox class by number: '
select LAB_RUNTIME_CLASS in "${RUNTIME_CLASSES[@]}"; do
  if [ -n "$LAB_RUNTIME_CLASS" ]; then
    k get runtimeclass "$LAB_RUNTIME_CLASS" -o yaml
    break
  fi
  printf '%s\n' 'Choose one of the listed numbers.' >&2
done
