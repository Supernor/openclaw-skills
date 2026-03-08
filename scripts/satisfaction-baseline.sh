#!/bin/bash

echo -e "AGENT NAME\tSCORE\tFLAGS"
echo -e "----------\t-----\t-----"

for agent_dir in /root/.openclaw/workspace-spec-*/; do
    AGENT_NAME=$(basename "$(echo "$agent_dir" | sed 's/\/$//')")
    SCORE=0
    FLAGS=""

    # 1. Role Clarity (30 points)
    SOUL_MD="$agent_dir/SOUL.md"
    if [ -f "$SOUL_MD" ]; then
        SCORE=$((SCORE + 10))
        SOUL_CONTENT=$(cat "$SOUL_MD" 2>/dev/null)
        if grep -q "Identity" <<< "$SOUL_CONTENT"; then
            SCORE=$((SCORE + 5))
        else
            FLAGS+="NoIdentity "
        fi
        if grep -q "Purpose" <<< "$SOUL_CONTENT"; then
            SCORE=$((SCORE + 5))
        else
            FLAGS+="NoPurpose "
        fi
        if grep -q "Intents" <<< "$SOUL_CONTENT"; then
            SCORE=$((SCORE + 10))
        else
            FLAGS+="NoIntents "
        fi
    else
        FLAGS+="NoSOUL "
    fi

    # 2. Skill Count (20 points)
    SKILLS_DIR="$agent_dir/skills"
    if [ -d "$SKILLS_DIR" ]; then
        NUM_SKILLS=$(find "$SKILLS_DIR" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l)
        SKILL_SCORE=$((NUM_SKILLS * 4))
        if [ "$SKILL_SCORE" -gt 20 ]; then
            SKILL_SCORE=20
        fi
        SCORE=$((SCORE + SKILL_SCORE))
    else
        FLAGS+="NoSkillsDir "
    fi

    # 3. Context Load (25 points)
    TOTAL_MD_CHARS=0
    for md_file in "$agent_dir"/*.md; do
        if [ -f "$md_file" ]; then
            CHARS=$(wc -m < "$md_file" 2>/dev/null)
            TOTAL_MD_CHARS=$((TOTAL_MD_CHARS + CHARS))
        fi
    done

    if [ "$TOTAL_MD_CHARS" -gt 500 ]; then
        SCORE=$((SCORE + 25))
    else
        FLAGS+="LowContext "
    fi

    # 4. Broken Tooling (10 points)
    NUM_BROKEN_SYMLINKS=$(find "$agent_dir" -maxdepth 1 -type l ! -exec test -e {} \; -print 2>/dev/null | wc -l)
    if [ "$NUM_BROKEN_SYMLINKS" -eq 0 ]; then
        SCORE=$((SCORE + 10))
    else
        FLAGS+="BrokenTooling "
    fi

    # 5. Memory Health (15 points)
    MEMORY_MD="$agent_dir/MEMORY.md"
    if [ -s "$MEMORY_MD" ]; then
        SCORE=$((SCORE + 15))
    else
        FLAGS+="NoMemory "
    fi

    printf "%-30s\t%s\t%s\n" "$AGENT_NAME" "$SCORE" "$FLAGS"

done

exit 0
