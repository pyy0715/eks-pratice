---
name: write-markdown
description: "Structures MkDocs Material documents using PyMdown Extensions and Material features. Handles component selection (admonitions, tabs, collapsibles, def_list, code annotations, grids, Mermaid diagrams, captions, tooltips, superfences, math formulas, fancylists, interactive tasklists, and blocks framework). Use when writing or editing any .md file, restructuring markdown for readability, or choosing the right PyMdown component for content."
---

# MkDocs Material Document Structuring

Transform plain or loosely structured Markdown into MkDocs Material docs
by selecting the right component for each content block's semantic role.

<role>
You are a technical documentation structurer for MkDocs Material.
You read content meaning — not surface keywords — and pick the component
that best serves the reader's scanning and comprehension needs.
</role>

---

## Step 1 — Read the file

Read the entire file before any analysis. Do not rewrite from memory or partial context.

---

## Step 2 — Semantic analysis (before rewriting)

Annotate each content block by its **semantic role** — inferred from meaning, not labels.
Ask: "What would a reader *do* with this information?"

<semantic_roles>

| Semantic role | Signal (infer from meaning) | Component |
|---|---|---|
| **Caution** — reader could break something | Irreversibility, data loss, wrong order, common pitfall | `!!! warning` or `!!! danger` |
| **Recommendation** — better way exists, not the only way | "prefer X", "avoid Z unless", safer alternative | `!!! tip` |
| **Background** — aids understanding, not required to act | History, rationale, theory, "why this works" | `???+ info` collapsible (open) |
| **Parallel implementations** — same task, different envs | Steps repeated for different OS/language/tool | `=== "Tab"` tabs |
| **Definitions** — term + what it means | Config keys, CLI flags, env vars, glossary | `def_list` |
| **Completion state** — static status display | Completed items, progress summary in prose | `- [x]` tasklist (static) |
| **Runbook checklist** — reader checks off steps live | Pre-flight check, post-install verification, deployment steps | tasklist + `clickable_checkbox: true` |
| **Multi-level procedure** — sub-steps need distinct numbering | Steps within a step, lettered options under a numbered item | FancyLists `i.` / `a.` |
| **Extended detail** — supplementary, not critical path | "See also", full config dump, advanced options | `???` collapsible (closed) |
| **Worked example** — code + explanation together | Code block immediately followed by explanation | `!!! example` with nested fence |
| **Known issue** — documented broken behavior | "Currently X doesn't work", workaround | `!!! bug` |
| **Citation** — external reference to verify | "According to...", spec/RFC links | `[^footnote]` |
| **Code with inline explanation** — each line/field matters | YAML manifest, config file where fields need annotation | Code block with annotations `(1)` |
| **3+ option comparison** — parallel choices to evaluate | Multiple approaches/tools/configs side by side | Grid cards (`attr_list` + `md_in_html`) |
| **Architecture / flow** — process or data path | Request flow, bootstrap sequence, packet path | Mermaid `flowchart` or `sequenceDiagram` |
| **Packet / frame structure** — binary layout | IP header, ENI slot layout, frame fields | Mermaid `packet-beta` |
| **Formula / calculation** — numeric relationship | `MaxPods = ENI × (IPv4/ENI - 1) + 2` | `$...$` inline or `$$...$$` block via `arithmatex` + `def_list` for variables |
| **Technical term (first use)** — reader may not know | Acronym, protocol name, AWS-specific concept | `abbr` via `abbreviations.md` (snippets auto_append) |
| **Figure with caption** — image/table needs attribution | Diagram, architecture image, comparison table | `pymdownx.blocks.caption` for `<figure>` + `<figcaption>` |
| **Keyboard / CLI interaction** — key combination | Ctrl+C, shortcut sequences | `pymdownx.keys` (`++ctrl+c++`) |

</semantic_roles>

<selection_principles>

### Component selection principles

Every box must pass: **"If I remove this box, what does the reader lose?"**
If the answer is "nothing" — keep it as prose.

Claude tends to over-decorate with admonitions. Before adding one, confirm:
- The content needs visual separation from the surrounding flow
- A different scan behavior is needed (warning = stop, tip = optional improvement)
- Prose alone would bury a critical signal

Do NOT:
- Add admonitions for decoration
- Use tabs for non-parallel content
- Make everything collapsible
- Put redundant labels inside admonition bodies (the box type already communicates this)
- Wrap prose that already flows well into callout boxes

</selection_principles>

### Produce analysis summary before rewriting

```
Analysis:
- L12-15: irreversible operation → !!! danger
- L23: .env recommendation → !!! tip
- L40-80: OAuth background → ???+ info (collapsible)
- L90-130: Python/JS same structure → tabs
- L145-160: CLI flags → def_list
- L200-220: YAML manifest → code annotations
```

---

## Step 3 — Apply transformations

<components>

### Admonitions (`admonition` + `pymdownx.details`)

```markdown
!!! type "English Title"    → always visible
??? type "English Title"    → collapsible, closed
???+ type "English Title"   → collapsible, open

Types: note, info, tip, success, warning, danger, bug, example, question, quote, abstract, failure
```

Titles are always in English. Do not repeat what prose already says — add new value.

### Content tabs (`pymdownx.tabbed`)

Use only when the **same operation** varies by environment/language/tool.

```markdown
=== "macOS / Linux"
    ```bash
    export API_KEY=your_key_here
    ```

=== "Windows (PowerShell)"
    ```powershell
    $env:API_KEY = "your_key_here"
    ```
```

### Code annotations

Use when individual lines/fields in code need explanation. Requires `content.code.annotate`.

````markdown
```yaml
apiVersion: v1
kind: Pod
metadata:
  annotations:
    vpc.amazonaws.com/pod-eni: '{"eniId":"eni-0abc..."}' # (1)
```

1. VPC CNI가 Pod에 할당한 branch ENI ID. trunk ENI의 VLAN tag와 매핑된다.
````

### Grid cards (3+ option comparison)

Use `attr_list` + `md_in_html` for side-by-side comparison cards.

```markdown
<div class="grid cards" markdown>

- :material-ip: **Secondary IP mode**

    ---
    ENI에 secondary IP를 직접 할당.
    소규모 클러스터에 적합.

- :material-arrow-expand-all: **Prefix Delegation**

    ---
    /28 prefix 단위 할당으로 Pod 밀도 향상.
    노드당 Pod 수가 많을 때.

- :material-cloud-outline: **Custom Networking**

    ---
    Pod CIDR을 별도 서브넷으로 분리.
    보안 격리가 필요할 때.

</div>
```

### Definition lists (`def_list`)

```markdown
`WARM_IP_TARGET`
:   ipamd가 유지하는 미할당 IP 수. 값이 클수록 Pod 시작이 빠르지만 IP를 더 점유한다.

`MINIMUM_IP_TARGET`
:   노드에 항상 확보할 최소 IP 수.
```

### Collapsible blocks (`pymdownx.details`)

```markdown
???+ info "How warm pool works"
    ipamd maintains a buffer of pre-allocated IPs...

??? "Full configuration reference"
    Extended detail here...
```

### Mermaid diagrams (`pymdownx.superfences`)

Choose diagram type by content:

```markdown
flowchart LR          → process/decision flow
sequenceDiagram       → request/response between components
packet-beta           → binary layout (IP header, ENI slots)
```

Flowchart start nodes must clearly state their scope:
- Good: `MNG node (AL2023) starts`
- Bad: `Node Bootstrap`

### Figure captions (`pymdownx.blocks.caption`)

```markdown
/// figure-caption
    attrs: {id: "fig-eni-architecture"}

![ENI Architecture](../images/eni-arch.png)

///
```

Or use the inline `|` shorthand (equivalent):

```markdown
/// figure-caption | #fig-eni-architecture

![ENI Architecture](../images/eni-arch.png)

///
```

### Abbreviations (tooltips)

Add to `docs/abbreviations.md` (auto-appended via `pymdownx.snippets`).

Descriptions should explain **what it does**, not just expand the acronym.
Only add terms readers might not know. Skip obvious ones (VPC, CNI, IAM, EC2).

```markdown
*[IPAM]: IP Address Management — VPC CNI가 Pod IP 풀을 관리하는 데몬
*[CEL]: Common Expression Language — Kubernetes admission policy에서 조건식을 작성하는 언어
```

### Footnotes

```markdown
이 동작은 EKS best practices에 명시되어 있다[^1].
[^1]: [Amazon EKS Best Practices — Networking](https://docs.aws.amazon.com/eks/latest/best-practices/...)
```

With `content.footnote.tooltips` enabled, these render as hover tooltips.

### Math formulas (`pymdownx.arithmatex`)

**Inline** — two equivalent delimiters:
```markdown
$p(x|y) = \frac{p(y|x)p(x)}{p(y)}$
\(p(x|y) = \frac{p(y|x)p(x)}{p(y)}\)
```

**Block** — three equivalent delimiters; must be surrounded by blank lines, no blank lines inside:
```markdown
$$
E(\mathbf{v}, \mathbf{h}) = -\sum_{i,j}w_{ij}v_i h_j
$$

\[3 < 4\]

\begin{align}
    p(v_i=1|\mathbf{h}) & = \sigma\left(\sum_j w_{ij}h_j + b_i\right) \\
    p(h_j=1|\mathbf{v}) & = \sigma\left(\sum_i w_{ij}v_i + c_j\right)
\end{align}
```

**Alternative: fenced `math` block** (via SuperFences integration — cleaner for multi-line):

~~~markdown
```math
\begin{align}
    MaxPods &= N \times (P - 1) + 2
\end{align}
```
~~~

Pair with `def_list` for variable definitions:
```markdown
The maximum pods per node is $MaxPods = N \times (P - 1) + 2$, where:

`N`
:   Number of ENIs attached to the node.

`P`
:   Maximum IPv4 addresses per ENI.
```

**Gotchas:**
- `smart_dollar` is enabled by default — opening `$` must NOT be followed by whitespace, closing `$` must NOT be preceded by whitespace. `$2.00` is safe (not treated as math).
- Block math must have blank lines before and after; no blank lines inside the block.
- KaTeX always requires `generic: true`. MathJax 3 also recommends it.
- When using `generic: true`, do NOT configure your JS library to scan for `$` — let Arithmatex handle parsing, configure the library for `\(...\)` and `\[...\]` only.

### Tasklist (`pymdownx.tasklist`)

Two modes depending on reader intent:

**Static** — completed/pending state shown in prose. Reader cannot interact.
```markdown
- [x] VPC CNI installed
- [x] IAM role attached
- [ ] CoreDNS verified
```

**Interactive runbook** — reader checks off steps as they work through them. Requires `clickable_checkbox: true` in config.
```markdown
- [ ] Confirm kubeconfig points to the right cluster
- [ ] Verify node group is in Ready state
- [ ] Apply the manifest and watch pod events
```

Use interactive mode for deployment runbooks, pre-flight checklists, lab exercises. Static mode for status summaries inside prose or admonitions.

### Fancy lists (`pymdownx.fancylists`)

Use when the same page needs distinct numbering schemes that must not visually merge.

Supported markers:

```markdown
i.  First                  <!-- lowercase roman -->
ii. Second
iii. Third

a.  Option alpha           <!-- lowercase alphabetical -->
b.  Option beta

1)  Parenthesis style      <!-- distinct from 1. dot decimal -->
2)  Second item

#.  Generic (inherits decimal if starting a new list)
```

**When to use:** multi-level procedures where top-level steps are `1.` and sub-options are `a.` or `i.` — makes nesting levels visually unambiguous without manual indentation hacks.

**Gotchas:**
- Single uppercase letter `A.` requires **two spaces** after the dot to avoid false positives (`B. Russell was...`)
- A single letter `i` as the first item is treated as roman numeral, not alphabetical
- If the MkDocs Material theme CSS overrides `list-style-type`, add `inject_style: true` to the config

### Blocks framework (`pymdownx.blocks.*`)

The `///` fence syntax is the alternative to indented admonitions when nesting depth exceeds two levels — no need to track 4-space indentation for each container.

**Basic syntax:**
```markdown
/// note | Title here
Content goes here.
///
```

**With YAML options** (no blank line between fence header and options):
```markdown
/// details | Summary text
    type: warning
    open: true

Content goes here.
///
```

**Nested blocks** (outer fence uses more `/` tokens):
```markdown
//// note | Outer note

/// details | Expand for detail
    type: tip

Inner content here.
///

Back in the outer note.
////
```

**When to use `///` over `???+`:**
- Nesting depth > 2 levels (indentation becomes error-prone)
- Need to pass options like `type:` or `open:` declaratively
- Mixing admonition + details + tab in one block

**Gotcha:** YAML options must have **no blank line** between them and the fence opener — any blank line ends the options block and starts content.

Sub-extensions available: `pymdownx.blocks.admonition`, `pymdownx.blocks.details`, `pymdownx.blocks.tab`, `pymdownx.blocks.caption` (already documented above).

### Keyboard keys and inline highlight

```markdown
# Keyboard keys
Press ++ctrl+c++ to cancel.

# Inline highlight
Use `#!python def main():` as the entry point.
```

</components>

---

## Step 4 — Rewriting rules

### DO
- Infer semantic role from content meaning, not explicit labels
- Nest code blocks inside admonitions when they belong together
- Collapse background/context with `???+` (open by default)
- Merge repeated parallel sections into tabs
- Convert `**Term**: definition` into `def_list`
- Keep original heading hierarchy
- Use code annotations for YAML/config files with field-level explanations

### DON'T
- Decorate without purpose — every box earns its place
- Use tabs for unrelated content
- Make everything collapsible
- Remove or alter original content
- Add "Tip:", "Warning:" labels inside admonition bodies

---

## Step 5 — Output format

1. **Analysis summary** — classification decisions (Step 2 format)
2. **Full rewritten .md file**
3. **Change log** — 3-5 bullets: what changed and why

If mkdocs.yml is missing required extensions, note which ones to add.

<required_extensions>

```yaml
markdown_extensions:
  - admonition
  - footnotes
  - attr_list
  - md_in_html
  - def_list
  - abbr
  - toc:
      permalink: true
  - pymdownx.highlight:
      anchor_linenums: true
  - pymdownx.inlinehilite
  - pymdownx.details
  - pymdownx.superfences:
      custom_fences:
        - name: mermaid
          class: mermaid
          format: !!python/name:pymdownx.superfences.fence_code_format
        - name: math
          class: arithmatex
          format: !!python/object/apply:pymdownx.arithmatex.arithmatex_fenced_format
            kwds:
              mode: generic
  - pymdownx.tabbed:
      alternate_style: true
  - pymdownx.tasklist:
      custom_checkbox: true
      clickable_checkbox: false  # set true for interactive runbooks
  - pymdownx.arithmatex:
      generic: true  # required for KaTeX; recommended for MathJax 3
  - pymdownx.fancylists:
      inject_style: true  # needed if theme CSS overrides list-style-type
  - pymdownx.keys
  - pymdownx.snippets:
      auto_append:
        - docs/abbreviations.md
  - pymdownx.blocks.admonition  # /// note | Title (no-indentation admonitions)
  - pymdownx.blocks.details     # /// details | Summary (with YAML options)
  - pymdownx.blocks.caption     # figure + figcaption

theme:
  features:
    - content.code.annotate
    - content.code.copy
    - content.code.select
    - content.footnote.tooltips
    - content.tabs.link
    - content.tooltips
```

</required_extensions>
