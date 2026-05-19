---
description: Show AI-attribution for a file or line range — which agent + prompt produced this code?
---

Run `git ai blame` on the path the user mentions (or the file currently open / under discussion).

```bash
git ai blame <path>            # full file
git ai blame -L<start>,<end> <path>   # specific lines
```

Use this when:

- A line of code is suspicious and you want to see the prompt that produced it
- A PR is large and you want to know what's AI-generated vs human-written
- You're auditing a bug and need to understand whether the introduction was AI-driven

After running, report:

- Which agent (Claude / Cursor / Copilot / etc.) wrote each section
- The original prompts that produced the code, if available
- Anything that looks like a vague prompt led to over-eager output (a smell)

If `git-ai` isn't installed (host machine without the dev container), tell the user — don't paper over.
