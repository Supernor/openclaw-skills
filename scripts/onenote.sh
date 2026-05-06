#!/bin/bash
# OneNote API tool for Relay (works inside container or on host)
#
# Usage:
#   onenote.sh list-notebooks
#   onenote.sh list-sections <notebook-id>
#   onenote.sh list-pages <section-id>
#   onenote.sh read-page <page-id>
#   onenote.sh create-page <section-id> <title> <html-body>
#   onenote.sh append-page <page-id> <html-content>
#   onenote.sh search <query>

set -euo pipefail

# Token location — same path works on host and in container (bind mount)
for TOKEN_PATH in \
    /home/node/.openclaw/credentials/onenote-access-token \
    /root/.openclaw/credentials/onenote-access-token; do
    if [ -f "$TOKEN_PATH" ]; then
        TOKEN=$(cat "$TOKEN_PATH")
        break
    fi
done

if [ -z "${TOKEN:-}" ]; then
    echo "Error: No OneNote access token found. Run onenote-auth.py on host first." >&2
    exit 1
fi

GRAPH="https://graph.microsoft.com/v1.0/me/onenote"
AUTH="Authorization: Bearer $TOKEN"

# Use node for JSON formatting (available in container), fall back to raw output
fmt_list() {
    local fields="$1"
    node -e "
        let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>{
            try{const j=JSON.parse(d);
            if(j.error){console.error(j.error.message);process.exit(1)}
            (j.value||[]).forEach(v=>{console.log(${fields})})
            }catch(e){console.log(d)}
        })
    " 2>/dev/null || cat
}

cmd="${1:-help}"
shift || true

case "$cmd" in
    list-notebooks)
        curl -s -H "$AUTH" "$GRAPH/notebooks" | fmt_list 'v.id+"\t"+v.displayName'
        ;;

    list-sections)
        NB_ID="${1:?notebook-id required}"
        curl -s -H "$AUTH" "$GRAPH/notebooks/$NB_ID/sections" | fmt_list 'v.id+"\t"+v.displayName'
        ;;

    list-pages)
        SECTION_ID="${1:?section-id required}"
        curl -s -H "$AUTH" "$GRAPH/sections/$SECTION_ID/pages?\$select=id,title,createdDateTime,lastModifiedDateTime&\$orderby=lastModifiedDateTime%20desc&\$top=20" \
            | fmt_list 'v.id+"\t"+(v.lastModifiedDateTime||"").slice(0,16)+"\t"+v.title'
        ;;

    read-page)
        PAGE_ID="${1:?page-id required}"
        curl -s -H "$AUTH" "$GRAPH/pages/$PAGE_ID/content"
        ;;

    create-page)
        SECTION_ID="${1:?section-id required}"
        TITLE="${2:?title required}"
        BODY="${3:-}"
        HTML="<!DOCTYPE html><html><head><title>$TITLE</title></head><body>$BODY</body></html>"
        curl -s -X POST -H "$AUTH" \
            -H "Content-Type: text/html" \
            -d "$HTML" \
            "$GRAPH/sections/$SECTION_ID/pages" | fmt_list 'v.id+"\t"+v.title'
        ;;

    append-page)
        PAGE_ID="${1:?page-id required}"
        CONTENT="${2:?html-content required}"
        PATCH='[{"target":"body","action":"append","content":"'"$(echo "$CONTENT" | sed 's/"/\\"/g')"'"}]'
        curl -s -X PATCH -H "$AUTH" \
            -H "Content-Type: application/json" \
            -d "$PATCH" \
            "$GRAPH/pages/$PAGE_ID/content"
        echo "OK"
        ;;

    search)
        QUERY="${1:?search query required}"
        curl -s -H "$AUTH" \
            "https://graph.microsoft.com/v1.0/me/onenote/pages?\$search=%22$(echo "$QUERY" | sed 's/ /%20/g')%22&\$select=id,title,parentSection&\$top=10" \
            | fmt_list 'v.id+"\t"+v.title'
        ;;

    help|*)
        echo "OneNote API Tool"
        echo ""
        echo "Commands:"
        echo "  list-notebooks                     List all notebooks"
        echo "  list-sections <notebook-id>        List sections in a notebook"
        echo "  list-pages <section-id>            List pages in a section"
        echo "  read-page <page-id>                Read page content (HTML)"
        echo "  create-page <section-id> <title> [html-body]  Create a new page"
        echo "  append-page <page-id> <html>       Append content to a page"
        echo "  search <query>                     Search pages by content"
        ;;
esac
