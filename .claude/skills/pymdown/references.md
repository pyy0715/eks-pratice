# PyMdown Component Examples — Before & After

A reference of common transformation patterns.

---

## 1. Plain blockquote → Admonition

**Before:**
```markdown
> **Note:** Make sure to back up your data before running this command.
```

**After:**
```markdown
!!! warning "Back up first"
    Make sure to back up your data before running this command.
```

---

## 2. Inline "Tip:" text → Tip admonition

**Before:**
```markdown
You can also use `--verbose` for more output. Tip: combine with `--log-file` to save logs.
```

**After:**
```markdown
You can also use `--verbose` for more output.

!!! tip
    Combine `--verbose` with `--log-file` to persist logs to disk.
```

---

## 3. Repeated language sections → Tabs

**Before:**
```markdown
### Python
```python
import requests
r = requests.get("https://api.example.com")
```

### JavaScript
```js
const r = await fetch("https://api.example.com");
```

### curl
```bash
curl https://api.example.com
```
```

**After:**
```markdown
=== "Python"
    ```python
    import requests
    r = requests.get("https://api.example.com")
    ```

=== "JavaScript"
    ```js
    const r = await fetch("https://api.example.com");
    ```

=== "curl"
    ```bash
    curl https://api.example.com
    ```
```

---

## 4. Long background section → Collapsible

**Before:**
```markdown
## Background

OAuth 2.0 is an authorization framework that enables applications to obtain
limited access to user accounts... [3 paragraphs of context]
```

**After:**
```markdown
??? info "Background — What is OAuth 2.0?"
    OAuth 2.0 is an authorization framework that enables applications to obtain
    limited access to user accounts... [3 paragraphs of context]
```

---

## 5. Bold-term definitions → Definition list

**Before:**
```markdown
- **Access Token**: A short-lived token used to authenticate API requests.
- **Refresh Token**: A long-lived token used to obtain new access tokens.
- **Scope**: Defines what resources the token can access.
```

**After:**
```markdown
Access Token
:   A short-lived token used to authenticate API requests.

Refresh Token
:   A long-lived token used to obtain new access tokens.

Scope
:   Defines what resources the token can access.
```

---

## 6. Numbered steps with code → Admonition or nested blocks

**Before:**
```markdown
1. Install dependencies
Run `pip install -r requirements.txt`

2. Set environment variables
Copy `.env.example` to `.env` and fill in the values.

3. Run the server
Execute `python main.py`
```

**After:**
```markdown
1. **Install dependencies**

    ```bash
    pip install -r requirements.txt
    ```

2. **Set environment variables**

    Copy `.env.example` to `.env` and fill in the values.

    !!! tip
        See [Configuration](config.md) for all available variables.

3. **Run the server**

    ```bash
    python main.py
    ```
```

---

## 7. TODO list → Tasklist

**Before:**
```markdown
Things left to do:
- Set up CI/CD
- Write unit tests
- Deploy to staging (done)
- Update documentation (done)
```

**After:**
```markdown
- [x] Deploy to staging
- [x] Update documentation  
- [ ] Set up CI/CD
- [ ] Write unit tests
```

---

## 8. Danger zone / destructive actions

**Before:**
```markdown
WARNING: This action cannot be undone. All data will be permanently deleted.
```

**After:**
```markdown
!!! danger "Irreversible action"
    This action **cannot be undone**. All data will be permanently deleted.
    Make sure you have a backup before proceeding.
```

---

## 9. Code + explanation pairs → Example admonition with nested fence

**Before:**
```markdown
Here's how the config file should look:

```yaml
server:
  port: 8080
  host: 0.0.0.0
```

The `port` field is required. `host` defaults to `localhost` if omitted.
```

**After:**
````markdown
!!! example "Minimal configuration"
    ```yaml
    server:
      port: 8080       # required
      host: 0.0.0.0    # defaults to localhost
    ```

    The `port` field is required. `host` defaults to `localhost` if omitted.
````

---

## 10. External references / citations → Footnotes

**Before:**
```markdown
This approach follows the 12-factor app methodology. See https://12factor.net for details.
```

**After:**
```markdown
This approach follows the 12-factor app methodology[^12factor].

[^12factor]: [The Twelve-Factor App](https://12factor.net) — a methodology for building modern, scalable software-as-a-service apps.
```
