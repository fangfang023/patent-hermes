# Claude Code Hooks

This directory contains hooks that enhance your Claude Code development experience with intelligent context injection for multi-agent workflows.

## Architecture

```
Claude Code Lifecycle
        │
        ├── PreToolUse ──────► Context Injector (Subagents)
        │
        ├── Tool Execution
        │
        ├── PostToolUse
        │
        ├── Notification
        │
        └── Stop/SubagentStop
```

These hooks execute at specific points in Claude Code's lifecycle, providing deterministic control over AI behavior.

## Available Hooks

### Subagent Context Injector (`subagent-context-injector.sh`)

**Purpose**: Automatically includes core project documentation in all sub-agent Task prompts, ensuring consistent context across multi-agent workflows.

**Trigger**: `PreToolUse` for `Task` tool

**Features**:
- Intercepts all Task tool calls before execution
- Prepends references to three core documentation files:
  - `docs/CLAUDE.md` - Project overview, coding standards, AI instructions
  - `docs/ai-context/project-structure.md` - Complete file tree and tech stack
  - `docs/ai-context/docs-overview.md` - Documentation architecture
- Passes through non-Task tools unchanged
- Preserves original task prompt by prepending context
- Enables consistent knowledge across all sub-agents
- Eliminates need for manual context inclusion in Task prompts

**Benefits**:
- Every sub-agent starts with the same foundational knowledge
- No manual context specification needed in each Task prompt
- Token-efficient through @ references instead of content duplication
- Update context in one place, affects all sub-agents
- Clean operation with simple pass-through for non-Task tools

## Installation

1. **Copy the hooks to your project**:
   ```bash
   cp -r hooks your-project/.claude/
   ```

2. **Configure hooks in your project**:
   Add to your Claude Code `settings.json`:

   ```json
   {
     "hooks": {
       "PreToolUse": [
         {
           "matcher": "Task",
           "hooks": [
             {
               "type": "command",
               "command": "${WORKSPACE}/.claude/hooks/subagent-context-injector.sh"
             }
           ]
         }
       ]
     }
   }
   ```

3. **Test the hooks**:
   ```bash
   # View logs
   tail -f .claude/logs/context-injection.log
   ```

## Security Model

1. **Execution Context**: Hooks run with full user permissions
2. **Non-blocking**: Uses exit code 0 to continue execution
3. **Data Flow**: Hooks can modify tool inputs via JSON transformation
4. **Isolation**: Each hook runs in its own process
5. **Logging**: All events logged to `.claude/logs/`

## Best Practices

1. **Hook Design**:
   - Fail gracefully - never break the main workflow
   - Log important events for debugging
   - Keep execution time minimal

2. **Configuration**:
   - Use `${WORKSPACE}` variable for portability
   - Keep hooks executable (`chmod +x`)
   - Version control hook configurations
   - Document custom modifications

## Troubleshooting

### Hooks not executing
- Check file permissions: `chmod +x *.sh`
- Verify paths in settings.json
- Check Claude Code logs for errors

## Extension Points

The hook system is designed for extensibility:

1. **Custom Hooks**: Add new scripts following the existing patterns
2. **Event Handlers**: Configure hooks for any Claude Code event
3. **Pattern Updates**: Modify context injection patterns for your needs
