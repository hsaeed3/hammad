#!/usr/bin/env bash
# Flattens skills/<category>/<skill>/ (and skills/<skill>/) into
# .agents/skills/<skill>/ and .claude/skills/<skill>/.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
skills_src="$root/skills"
agents_dest="$root/.agents/skills"
claude_dest="$root/.claude/skills"
cursor_dest="$root/.cursor/skills"
name_re='^[a-z0-9][a-z0-9-]*[a-z0-9]$|^[a-z0-9]$'

if [[ ! -d "$skills_src" ]]; then
    echo "error: skills directory not found: $skills_src" >&2
    exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
    echo "error: jq is required to generate .claude-plugin/plugin.json and marketplace.json" >&2
    exit 1
fi

names=()
paths=()

# Extracts the frontmatter `name:` value from a SKILL.md, stripping quotes.
frontmatter_name() {
    awk '/^---[[:space:]]*$/{c++; next} c==1' "$1" \
        | sed -n 's/^name:[[:space:]]*//p' \
        | head -1 \
        | sed -E "s/^['\"]//; s/['\"][[:space:]]*\$//"
}

# Registers a candidate skill directory after validating it.
add_skill() {
    local dir="$1" name skill_md fm_name
    name="$(basename "$dir")"
    skill_md="$dir/SKILL.md"

    if [[ ! -f "$skill_md" ]]; then
        echo "warn: skipping '$dir' (no SKILL.md)" >&2
        return
    fi
    if [[ ! "$name" =~ $name_re ]] || [[ "$name" == *--* ]]; then
        echo "error: invalid skill directory name '$name' (lowercase letters, numbers, hyphens only): $dir" >&2
        exit 1
    fi
    fm_name="$(frontmatter_name "$skill_md")"
    if [[ -z "$fm_name" ]]; then
        echo "error: '$skill_md' is missing a 'name:' field in its frontmatter" >&2
        exit 1
    fi
    if [[ "$fm_name" != "$name" ]]; then
        echo "error: '$skill_md' has name '$fm_name' but lives in directory '$name' — they must match" >&2
        exit 1
    fi

    names+=("$name")
    paths+=("$dir")
}

# Pass 1: discover skills. skills/ holds either a skill directly, or a
# category dir one level deep whose children are guaranteed skills.
shopt -s nullglob
for entry in "$skills_src"/*/; do
    entry="${entry%/}"

    if [[ -f "$entry/SKILL.md" ]]; then
        add_skill "$entry"
        continue
    fi

    children=("$entry"/*/)
    if [[ ${#children[@]} -eq 0 ]]; then
        echo "warn: skipping empty directory: $entry" >&2
        continue
    fi

    for sub in "${children[@]}"; do
        sub="${sub%/}"
        if [[ -f "$sub/SKILL.md" ]]; then
            add_skill "$sub"
        elif [[ -n "$(find "$sub" -mindepth 1 -maxdepth 1 -type d)" ]]; then
            echo "error: '$sub' has no SKILL.md but contains subdirectories — skills/ only supports skills/<category>/<skill>/, not deeper nesting" >&2
            exit 1
        else
            echo "warn: skipping '$sub' (no SKILL.md)" >&2
        fi
    done
done

if [[ ${#names[@]} -eq 0 ]]; then
    echo "warn: no skills found under $skills_src; leaving $agents_dest, $claude_dest, and $cursor_dest untouched" >&2
    exit 0
fi

# Detect duplicate skill names across different category subdirs before
# writing anything, so a bad run never partially clobbers the output dirs.
dupes="$(printf '%s\n' "${names[@]}" | sort | uniq -d)"
if [[ -n "$dupes" ]]; then
    echo "error: duplicate skill name(s) found across skills/:" >&2
    while IFS= read -r dupe; do
        echo "  '$dupe' defined in:" >&2
        for i in "${!names[@]}"; do
            [[ "${names[$i]}" == "$dupe" ]] && echo "    - ${paths[$i]}" >&2
        done
    done <<<"$dupes"
    exit 1
fi

rm -rf "$agents_dest" "$claude_dest" "$cursor_dest"
mkdir -p "$agents_dest" "$claude_dest" "$cursor_dest"

for i in "${!names[@]}"; do
    cp -R "${paths[$i]}" "$agents_dest/${names[$i]}"
    cp -R "${paths[$i]}" "$claude_dest/${names[$i]}"
    cp -R "${paths[$i]}" "$cursor_dest/${names[$i]}"
    # A skill's nested agents/ dir holds per-provider config (openai.yaml,
    # gemini.toml, ...) — relevant to .agents/, not to Claude's/Cursor's own skills.
    rm -rf "$claude_dest/${names[$i]}/agents"
    rm -rf "$cursor_dest/${names[$i]}/agents"
    echo "installed: ${names[$i]}"
done

echo "done: ${#names[@]} skill(s) exported to .agents/skills, .claude/skills, and .cursor/skills"

# Bundle every exported skill into a single Claude Code plugin + marketplace,
# so the whole repo installs as one `/plugin install <name>@<name>`.
# Metadata is pulled from pyproject.toml's [project] table (already the
# source of truth for name/version/author) rather than invented here.
plugin_dir="$root/.claude-plugin"
pyproject="$root/pyproject.toml"

plugin_name="$(basename "$root")"
plugin_version="0.0.0"
plugin_description=""
author_name="Unknown"
author_email=""

if [[ -f "$pyproject" ]]; then
    project_section="$(awk '/^\[project\]/{f=1; next} /^\[/{f=0} f' "$pyproject")"
    v="$(sed -n 's/^version[[:space:]]*=[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p' <<<"$project_section" | head -1)"
    [[ -n "$v" ]] && plugin_version="$v"
    v="$(sed -n 's/^description[[:space:]]*=[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p' <<<"$project_section" | head -1)"
    [[ -n "$v" ]] && plugin_description="$v"
    v="$(sed -n 's/.*authors[[:space:]]*=.*name[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' <<<"$project_section" | head -1)"
    [[ -n "$v" ]] && author_name="$v"
    v="$(sed -n 's/.*authors[[:space:]]*=.*email[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' <<<"$project_section" | head -1)"
    [[ -n "$v" ]] && author_email="$v"
fi

if [[ -z "$plugin_description" ]]; then
    plugin_description="Skills: $(
        IFS=', '
        echo "${names[*]}"
    )"
fi

mkdir -p "$plugin_dir"

jq -n \
    --arg name "$plugin_name" \
    --arg version "$plugin_version" \
    --arg description "$plugin_description" \
    --arg author_name "$author_name" \
    --arg author_email "$author_email" \
    '{
        name: $name,
        version: $version,
        description: $description,
        author: (
            {name: $author_name}
            + (if $author_email != "" then {email: $author_email} else {} end)
        ),
        skills: ["./.claude/skills/"]
    }' >"$plugin_dir/plugin.json"

jq -n \
    --arg schema "https://www.schemastore.org/claude-code-marketplace.json" \
    --arg name "$plugin_name" \
    --arg description "$plugin_description" \
    --arg owner_name "$author_name" \
    --arg owner_email "$author_email" \
    '{
        "$schema": $schema,
        name: $name,
        description: $description,
        owner: (
            {name: $owner_name}
            + (if $owner_email != "" then {email: $owner_email} else {} end)
        ),
        plugins: [
            {
                name: $name,
                description: $description,
                source: "./"
            }
        ]
    }' >"$plugin_dir/marketplace.json"

echo "done: wrote .claude-plugin/plugin.json and marketplace.json for '$plugin_name'"
