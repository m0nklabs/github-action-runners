#!/usr/bin/env bash
#
# detect-languages.sh — haal de talen van een repo op via de GitHub API en
# geef ze weer met percentages. Optioneel met --codeql map je op de CodeQL-
# taalnamen en filter je op de talen die CodeQL ondersteunt.
#
# Gebruik:
#   ./bin/detect-languages.sh m0nklabs/oelala
#   ./bin/detect-languages.sh --codeql m0nklabs/oelala
#   ./bin/detect-languages.sh --json m0nklabs/oelala
#
# Vereist: gh met een token met leestoegang tot de repo.

set -euo pipefail

CODEQL=0
JSON=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --codeql) CODEQL=1; shift ;;
    --json)   JSON=1;   shift ;;
    --)       shift; break ;;
    *)        break ;;
  esac
done

REPO="${1:?geef een repo op als owner/repo (bijv. m0nklabs/oelala)}"

# bytes per taal uit de GitHub API
if ! languages="$(gh api "/repos/${REPO}/languages")"; then
  echo "Kon de talen van ${REPO} niet ophalen via de GitHub API." >&2
  exit 1
fi

total_bytes=$(echo "$languages" | grep -oE ':[0-9]+' | sed 's/://' | awk '{s+=$1} END{print s}')
if [[ -z "$total_bytes" || "$total_bytes" == "0" ]]; then
  echo "Geen code-talen gevonden in ${REPO}." >&2
  exit 0
fi

# GitHub-linguist-taalnaam -> CodeQL-taalnaam (CodeQL ondersteunt deze alleen)
declare -A MAP=(
  [C]="c-cpp" [C++]="c-cpp" [C#]="csharp" [Go]="go"
  [Java]="java-kotlin" [Kotlin]="java-kotlin"
  [JavaScript]="javascript-typescript" [TypeScript]="javascript-typescript"
  [Python]="python" [Ruby]="ruby" [Swift]="swift"
)

emit() { # "$naam" "$percentage" "$codeql_naam"
  if [[ $JSON -eq 1 ]]; then
    printf '  {"%s": {"percentage": %s, "codeql": %s}}' "$1" "$2" "${3:+\\\"$3\\\"}"
  else
    printf '%-22s %6.2f%%' "$1" "$2"
    [[ -n "${3:-}" ]] && printf '   -> %s' "$3"
    printf '\n'
  fi
}

# parse de JSON en bereken percentages
echo "$languages" \
  | sed 's/[{}]//g; s/"//g; s/,/\n/g' \
  | tr -d ' ' \
  | grep -E '.+:[0-9]+' \
  | while IFS=: read -r name bytes; do
      pct=$(awk -v b="$bytes" -v t="$total_bytes" 'BEGIN{printf "%.2f", (b/t)*100}')
      if [[ $CODEQL -eq 1 ]]; then
        cql="${MAP[$name]:-}"
        if [[ -n "$cql" ]]; then emit "$name" "$pct" "$cql"; fi
      else
        emit "$name" "$pct" ""
      fi
    done
