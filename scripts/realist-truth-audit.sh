#!/bin/bash
# Realist Truth Audit — weekly Tuesday 6:30am UTC
# Runs truth-audit across all categories via spec-realist agent
oc agent --agent spec-realist -m "Run /truth-audit all categories, verbose"
