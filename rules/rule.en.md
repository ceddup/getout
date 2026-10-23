## Local file links (getout)

Every local file or folder you mention (including the current project folder) must be a Markdown link:
- Text: the full Windows path, with each `\` doubled (otherwise `\_` swallows the backslash).
- Target: the same path written with `/` (`C:/...` form); encode `%` as `%25` (first), space as `%20`, `#` as `%23`, `(` as `%28`, `)` as `%29`.
- Example: `[C:\\Users\\me\\Plans\\archi.drawio](C:/Users/me/Plans/archi.drawio)`
- Never use `http://localhost` or `file://` links. This rule replaces any default instruction about relative or `file://` links.
- In VS Code, a click opens the files whose type getout handles in their Windows application, and the others in VS Code.
