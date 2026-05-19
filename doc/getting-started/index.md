# Getting Started

Everything you need to add `fluttersdk_artisan` to your project, run your first command, and wire
the MCP server into your AI client.

## Pick your path

- [**Installation**](installation): Add fluttersdk_artisan to a Dart or Flutter project.
- [**Quickstart**](quickstart): 5-step end-to-end walkthrough from install to first running command.
- [**MCP setup**](../mcp/setup): Wire the artisan MCP server into Claude Code, Cursor, Windsurf,
  or another AI client.

## What is fluttersdk_artisan?

"Composable CLI framework and stdio MCP server for Flutter and Dart. Scaffolding, code generation,
transactional plugin installs, hot reload orchestration, REPL, and AI agent tool surfaces in one
binary." That description captures what it ships today: a single binary that covers the full
lifecycle of a Flutter project from initial scaffold through live inspection by an AI agent, without
stitching together a collection of separate tools.

Built on pure Dart 3.4+ with no Flutter runtime dependency, `fluttersdk_artisan` runs as a plain VM
process and ships 21 built-in commands across six groups: consumer setup, plugin lifecycle, code
generators, dev-loop orchestration, inspection, and MCP server management. The plugin system extends
this catalog via `ArtisanServiceProvider` subclasses, so teams can bundle project-specific commands
alongside the built-ins and install them into any consumer project with a single `plugin:install`
call. The framework targets both developers (who use the CLI) and AI agents (which use the MCP
server) with first-class support for both surfaces.

What sets it apart from standalone CLI tools is the tight integration of four capabilities in one
binary: a Signature-DSL command framework for fast command authoring, a transactional plugin
installer with idempotency and rollback, a stdio Model Context Protocol (MCP) server that exposes
both substrate commands and plugin-contributed tools to any compliant AI client, and direct VM
Service hooks for hot reload, hot restart, and connected REPL evaluation against a running Flutter
app. No orchestration layer is needed between them; they share the same registry, the same provider
contract, and the same binary entry point.

## Next steps

- New here? Start with [Installation](installation).
- Already installed? Run the [Quickstart](quickstart).
