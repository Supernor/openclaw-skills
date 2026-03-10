#!/bin/bash
# Realist Method Review — weekly Wednesday 6:30am UTC
# Runs method-review across full fleet via spec-realist agent
oc agent --agent spec-realist -m "Run /method-review full fleet"
