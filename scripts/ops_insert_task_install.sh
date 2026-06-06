#!/usr/bin/env bash
# ops_insert_task_install.sh — Ensure ops_insert_task MCP tool is available
# and create a helper to inject truth-gate nightly audit tasks

set -euo pipefail

OPSDB="/root/.openclaw/ops.db"
HELPER="/root/.openclaw/scripts/.ops_insert_helper.py"

# Create a tiny helper to invoke the gateway's ops_insert_task MCP tool
cat > "${HELPER}" << 'EOF'
#!/usr/bin/env python3
import sys, json, subprocess, os
TASK_FILE = '/tmp/task_meta.json'
HELPER = '/root/.openclaw/scripts/.ops_insert_helper.py'

# ops_insert_task takes one argument: a JSON file path containing meta + task text
def main():
    if len(sys.argv) != 2:
        print(json.dumps({"error": "Usage: .ops_insert_helper.py <meta_json_file>"}), file=sys.stderr)
        sys.exit(1)
    
    meta_file = sys.argv[1]
    try:
        with open(meta_file, 'r') as f:
            meta = json.load(f)
        task_text = meta.get('task')
        if not task_text:
            print(json.dumps({"error": "meta.task is required"}), file=sys.stderr)
            sys.exit(1)
        
        # Host can send via gateway MCP if it has network; or native Python\if False: 
        # TODO: later if gateway provides CLI
        cmd = [
            'openclaw', 'message', 'send', '--channel', 'gateway-mcp',
            '-m', json.dumps({"tool": "ops_insert_task", "payload": meta})
        ]
        subprocess.run(cmd, check=False)
        else:
        # Direct SQL for now, as executed by agent via gateway bridge but the task rows
        # are visible to MCP gateway and agents alike via ops.db access.
        ts = subprocess.check_output(['date', '-u', '+%Y-%m-%dT%H:%M:%SZ']).decode().strip()
        try:
            import sqlite3
            conn = sqlite3.connect('/root/.openclaw/ops.db')
            conn.execute("PRAGMA busy_timeout=5000")
            conn.execute(
                "INSERT INTO tasks (agent, status, task, context, meta) VALUES (?, 'pending', ?, ?, ?)",
                (meta.get('agent','spec-ops'), task_text, meta.get('context','automation'), json.dumps(meta.get('meta',{})))
            )
            task_id = conn.execute("SELECT last_insert_rowid()").fetchone()[0]
            conn.commit()
            conn.close()
            print(json.dumps({"task": task_text[:80], "task_id": task_id}))
        except Exception as e:
            print(json.dumps({"error": str(e)}), file=sys.stderr)
            sys.exit(1)

if __name__ == '__main__':
    main()
EOF

chmod +x "${HELPER}" 2>/dev/null || true

# Helper alias
echo "alias ops_insert_task='python3 ${HELPER}'" >> ~/.bashrc

# Validate helper executable
if [ -x "${HELPER}" ]; then
    echo "Helper installed and executable: ${HELPER}"
else
    echo "Warning: helper not executable; trying to fix" >&2
    chmod +x "${HELPER}" 2>/dev/null || true
fi
echo ""
