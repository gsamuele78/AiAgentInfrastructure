#!/usr/bin/env bash
# tests/skills/run.sh -- il lint delle skill sa promuovere e bocciare (fixture) e passa sul repo.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
P=0; F=0
ok(){ echo -e "  \033[32m✓\033[0m $1"; P=$((P+1)); }
ko(){ echo -e "  \033[31m✗\033[0m $1"; [ -n "${2:-}" ] && echo "$2" | sed 's/^/      /'; F=$((F+1)); }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
skill(){ mkdir -p "$1/$2"; printf -- '---\nname: %s\ndescription: %s\n---\n# %s\n' "${4:-$2}" "$3" "$2" > "$1/$2/SKILL.md"; }
expect(){ # expect <pass|fail:pattern> <descrizione> <root>
  out=$(python3 "$HERE/check.py" --root "$3" 2>&1); rc=$?
  case "$1" in
    pass) [ $rc = 0 ] && ok "$2" || ko "$2" "$out" ;;
    fail:*) [ $rc != 0 ] && grep -q "${1#fail:}" <<<"$out" && ok "$2" || ko "$2 (atteso ${1#fail:})" "$out" ;;
  esac
}
echo -e "\n\033[36m── skill (ADR-0019 §1-2)\033[0m"
r="$W/ok"; skill "$r/.agents/skills" adr "Scrive o supersede un ADR"; skill "$r/.agents/skills" infra-change "dry-run, snapshot, apply"
mkdir -p "$r/.claude"; ln -s ../.agents/skills "$r/.claude/skills"
expect pass "symlink .claude/skills -> .agents/skills: nessun duplicato" "$r"
r="$W/dup"; skill "$r/.agents/skills" adr "x"; skill "$r/.claude/skills" adr "x"
expect "fail:S2" "stessa skill in due cartelle vere: duplicato" "$r"
r="$W/builtin"; skill "$r/.agents/skills" code-review "x"
expect "fail:S3" "skill 'code-review': collide con l'integrata" "$r"
r="$W/name"; skill "$r/.agents/skills" adr "x" "adr-writer"
expect "fail:S1" "name diverso dalla cartella" "$r"
r="$W/nofm"; mkdir -p "$r/.agents/skills/x"; echo "# x" > "$r/.agents/skills/x/SKILL.md"
expect "fail:S1" "SKILL.md senza frontmatter" "$r"
expect pass "skill del repo" "$HERE/../.."
echo -e "\n  skill: \033[32m✓ $P\033[0m  \033[31m✗ $F\033[0m"
[ "$F" = 0 ]
