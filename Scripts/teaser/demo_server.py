"""Made-up MCP servers for the README picture (make-teaser.sh). Standard library only.

    demo_server.py notes|calendar|files [modern|legacy] [--http PORT]

stdio by default (one JSON-RPC message per line); with --http, a stateless Streamable HTTP server that
answers with plain JSON. Modern servers answer server/discover; legacy ones reject it and speak
initialize. They answer discovery and tools/list only: their tools exist to be looked at, not called.
"""
import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

MODERN = "2026-07-28"
LEGACY = "2025-06-18"


def tool(name, description=None, title=None, properties=None, required=None, annotations=None, output=None):
    entry = {"name": name}
    if title:
        entry["title"] = title
    if description is not None:
        entry["description"] = description
    schema = {"type": "object", "properties": properties or {}}
    if required:
        schema["required"] = required
    entry["inputSchema"] = schema
    if annotations:
        entry["annotations"] = annotations
    if output:
        entry["outputSchema"] = output
    return entry


READ_ONLY = {"readOnlyHint": True, "openWorldHint": False}

NOTES = {
    "info": {"name": "notes-server", "title": "Notes", "version": "1.4.0"},
    "instructions": (
        "Notes are plain text with a title, tags and a notebook. Search before you\n"
        "create, so a note is not written twice. Deleting a notebook deletes its\n"
        "notes; ask the user first."
    ),
    "tools": [
        tool(
            "search_notes",
            title="Search Notes",
            description=(
                "Search notes by text, tag or date.\n"
                "\n"
                "The query matches titles and bodies. Prefixes narrow it\n"
                "down and can be combined:\n"
                "\n"
                "- `tag:travel` finds notes with that tag\n"
                "- `after:2026-01-01` finds notes changed since then\n"
                "- `in:Work` searches one notebook only\n"
                "\n"
                "Returns at most `limit` notes, newest first, each with its\n"
                "id, title and the first lines of its body."
            ),
            properties={
                "query": {"type": "string", "description": "Words to find, with optional prefixes."},
                "limit": {"type": "integer", "description": "How many notes to return.", "default": 20, "minimum": 1, "maximum": 100},
                "include_archived": {"type": "boolean", "description": "Search archived notes too.", "default": False},
            },
            required=["query"],
            annotations=READ_ONLY,
        ),
        tool(
            "get_note",
            title="Get Note",
            description="Read one note in full: title, body, tags, notebook and dates.",
            properties={"id": {"type": "string", "description": "The note's id, as search_notes returns it."}},
            required=["id"],
            annotations={**READ_ONLY, "idempotentHint": True},
        ),
        tool(
            "create_note",
            title="Create Note",
            description=(
                "Create a note. The body is plain text; Markdown is kept as\n"
                "typed and not rendered. Tags that do not exist yet are\n"
                "created on the way."
            ),
            properties={
                "title": {"type": "string", "description": "Shown in lists and search results.", "maxLength": 200},
                "body": {"type": "string", "description": "The note's text."},
                "tags": {"type": "array", "items": {"type": "string"}, "description": "Tags to add."},
                "notebook": {"type": "string", "description": "Notebook to file it in.", "default": "Inbox"},
            },
            required=["title", "body"],
            annotations={"readOnlyHint": False, "destructiveHint": False, "openWorldHint": False},
            output={
                "type": "object",
                "properties": {"id": {"type": "string"}, "created": {"type": "string", "format": "date-time"}},
                "required": ["id"],
            },
        ),
        tool(
            "update_note",
            title="Update Note",
            description="Replace a note's title, body or tags. Fields left out stay as they are.",
            properties={
                "id": {"type": "string", "description": "The note to change."},
                "title": {"type": "string"},
                "body": {"type": "string"},
                "tags": {"type": "array", "items": {"type": "string"}},
            },
            required=["id"],
            annotations={"readOnlyHint": False, "destructiveHint": False, "idempotentHint": True, "openWorldHint": False},
        ),
        tool(
            "import_files",
            title="Import Files",
            description=(
                "Import text files from the notes folder as new notes.\n"
                "\n"
                "Patterns are relative to the notes folder. Examples:\n"
                "\"**/*.md\", \"journal/**/2026-*.txt\", \"todo.txt\".\n"
                "A pattern without a slash matches in every folder."
            ),
            properties={
                "patterns": {"type": "array", "items": {"type": "string"}, "description": "Glob patterns of files to import."},
                "notebook": {"type": "string", "description": "Notebook for the new notes.", "default": "Inbox"},
                "on_conflict": {"type": "string", "enum": ["skip", "rename", "replace"], "default": "skip",
                                "description": "What to do when a note with the same title exists."},
            },
            required=["patterns"],
            annotations={"readOnlyHint": False, "destructiveHint": False, "openWorldHint": False},
        ),
        tool(
            "export_notebook",
            title="Export Notebook",
            description="Export a notebook to a single file and return its path.",
            properties={
                "notebook": {"type": "string", "description": "The notebook to export."},
                "format": {"type": "string", "enum": ["markdown", "html", "pdf"], "default": "markdown", "description": "File format."},
                "options": {
                    "type": "object",
                    "description": "Fine-tuning for the export.",
                    "properties": {
                        "include_tags": {"type": "boolean", "default": True},
                        "page_size": {"type": "string", "enum": ["A4", "Letter"], "description": "PDF only."},
                    },
                },
            },
            required=["notebook"],
            annotations=READ_ONLY,
        ),
        tool(
            "archive_note",
            title="Archive Note",
            description="Move a note to the archive. Archived notes are left out of searches unless asked for.",
            properties={"id": {"type": "string", "description": "The note to archive."}},
            required=["id"],
            annotations={"readOnlyHint": False, "destructiveHint": False, "idempotentHint": True, "openWorldHint": False},
        ),
        tool(
            "delete_notebook",
            title="Delete Notebook",
            description=(
                "Delete a notebook and every note in it, archived ones\n"
                "included. This cannot be undone."
            ),
            properties={
                "notebook": {"type": "string", "description": "The notebook to delete."},
                "confirm": {"type": "string", "description": "The notebook's name again, as a safeguard."},
            },
            required=["notebook", "confirm"],
            annotations={"readOnlyHint": False, "destructiveHint": True, "openWorldHint": False},
        ),
        tool(
            "list_tags",
            title="List Tags",
            description="All tags with the number of notes carrying each.",
            annotations=READ_ONLY,
        ),
        tool(
            "merge_tags",
            properties={"from": {"type": "string"}, "into": {"type": "string"}},
            required=["from", "into"],
        ),
    ],
}

CALENDAR = {
    "info": {"name": "calendar-mcp", "version": "0.9.2"},
    "instructions": "Times are local unless they carry an offset. Ask before cancelling an event that has guests.",
    "tools": [
        tool("list_events", title="List Events", description="Events between two dates, ordered by start.",
             properties={"from": {"type": "string", "format": "date"}, "to": {"type": "string", "format": "date"}},
             required=["from", "to"], annotations=READ_ONLY),
        tool("find_free_time", title="Find Free Time",
             description="Free slots of at least `minutes` length on the given days,\nwithin working hours.",
             properties={"days": {"type": "array", "items": {"type": "string", "format": "date"}},
                         "minutes": {"type": "integer", "default": 30, "minimum": 5}},
             required=["days"], annotations=READ_ONLY),
        tool("create_event", title="Create Event", description="Create an event and invite its guests.",
             properties={"title": {"type": "string"}, "start": {"type": "string", "format": "date-time"},
                         "end": {"type": "string", "format": "date-time"},
                         "guests": {"type": "array", "items": {"type": "string", "format": "email"}}},
             required=["title", "start", "end"],
             annotations={"readOnlyHint": False, "destructiveHint": False, "openWorldHint": True}),
        tool("move_event", title="Move Event", description="Move an event to a new start time, keeping its length.",
             properties={"id": {"type": "string"}, "start": {"type": "string", "format": "date-time"}},
             required=["id", "start"],
             annotations={"readOnlyHint": False, "destructiveHint": False, "idempotentHint": True}),
        tool("cancel_event", title="Cancel Event", description="Cancel an event and tell its guests.",
             properties={"id": {"type": "string"}, "message": {"type": "string", "description": "Sent to the guests."}},
             required=["id"], annotations={"readOnlyHint": False, "destructiveHint": True, "openWorldHint": True}),
    ],
}

FILES = {
    "info": {"name": "files", "version": "2.1.0"},
    "instructions": None,
    "tools": [
        tool("read_file", title="Read File", description="Read a text file below the shared folder.",
             properties={"path": {"type": "string"}}, required=["path"], annotations=READ_ONLY),
        tool("list_folder", title="List Folder", description="Files and folders in a folder, with sizes.",
             properties={"path": {"type": "string", "default": "."}}, annotations=READ_ONLY),
        tool("write_file", title="Write File", description="Write a text file, replacing one that exists.",
             properties={"path": {"type": "string"}, "text": {"type": "string"}}, required=["path", "text"],
             annotations={"readOnlyHint": False, "destructiveHint": True}),
    ],
}

SERVERS = {"notes": NOTES, "calendar": CALENDAR, "files": FILES}


def answer(server, era, message):
    """The reply to one message, or None for a notification."""
    method, ident = message.get("method"), message.get("id")
    if ident is None:
        return None

    def result(value):
        return {"jsonrpc": "2.0", "id": ident, "result": value}

    def error(code, text):
        return {"jsonrpc": "2.0", "id": ident, "error": {"code": code, "message": text}}

    if method == "server/discover":
        if era != "modern":
            return error(-32601, "Method not found: server/discover")
        value = {
            "resultType": "complete",
            "supportedVersions": [MODERN],
            "capabilities": {"tools": {"listChanged": False}},
            "_meta": {"io.modelcontextprotocol/serverInfo": server["info"]},
        }
        if server["instructions"]:
            value["instructions"] = server["instructions"]
        return result(value)
    if method == "initialize":
        value = {"protocolVersion": LEGACY, "capabilities": {"tools": {}}, "serverInfo": server["info"]}
        if server["instructions"]:
            value["instructions"] = server["instructions"]
        return result(value)
    if method == "tools/list":
        value = {"tools": server["tools"]}
        if era == "modern":
            value["resultType"] = "complete"
        return result(value)
    if method == "ping":
        return result({})
    return error(-32601, f"Method not found: {method}")


def serve_stdio(server, era):
    print(f"{server['info']['name']} {server['info']['version']}: {len(server['tools'])} tools, ready on stdio",
          file=sys.stderr, flush=True)
    for line in sys.stdin:
        if not line.strip():
            continue
        reply = answer(server, era, json.loads(line))
        if reply is not None:
            sys.stdout.write(json.dumps(reply) + "\n")
            sys.stdout.flush()


def serve_http(server, era, port):
    class Handler(BaseHTTPRequestHandler):
        def do_POST(self):
            body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
            reply = answer(server, era, json.loads(body))
            if reply is None:
                self.send_response(202)
                self.end_headers()
                return
            data = json.dumps(reply).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def do_DELETE(self):
            self.send_response(405)
            self.end_headers()

    HTTPServer(("127.0.0.1", port), Handler).serve_forever()


if __name__ == "__main__":
    args = sys.argv[1:]
    port = None
    if "--http" in args:
        index = args.index("--http")
        port = int(args[index + 1])
        del args[index:index + 2]
    chosen = SERVERS[args[0]]
    era = args[1] if len(args) > 1 else "modern"
    if port:
        serve_http(chosen, era, port)
    else:
        serve_stdio(chosen, era)
