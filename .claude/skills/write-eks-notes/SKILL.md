---
name: write-eks-notes
description: "Organizes EKS study notes into polished, AWS-verified technical markdown documents. Verifies facts against official AWS docs, enriches concepts with design rationale, and cross-links with previous week documents. Use whenever the user shares EKS study content or drafts — networking, storage, security, autoscaling, or any other EKS topic."
---

# Writing EKS Notes

Workflow:
1. Study content arrives → save to staging file, reply with brief ack
2. User signals done → run Finalize steps below, then write doc using `write-markdown` rules

---

## Setup (runs once per topic)

On the first content message, scan for existing staging files:

```bash
ls docs/drafts/*-staging.md 2>/dev/null
```

If `docs/` does not exist in cwd, ask for the project root path first.

**If staging files exist**, show the list and ask:
- "Continue one of these, or start a new topic?"
- If continuing: use that file's WEEK/TOPIC from the header comments, skip questions
- If starting new: ask for week number and topic slug

**If no staging files exist**, ask:
1. Week number (e.g. `week2`) — determines `docs/week{N}/` output path
2. Topic slug (e.g. `vpc-cni`, `storage`, `autoscaling`) — used in filename

```bash
mkdir -p docs/drafts
cat > docs/drafts/week{N}-{topic}-staging.md << 'EOF'
<!-- WEEK: {N} -->
<!-- TOPIC: {topic} -->
<!-- CREATED: {date} -->
EOF
```

---

## Saving Content

Append each incoming message to the staging file:

```bash
cat >> docs/drafts/week{N}-{topic}-staging.md << 'EOF'---
name: writing-eks-notes
description: "Organizes EKS study notes into polished, AWS-verified technical markdown documents. Verifies facts against official AWS docs, enriches concepts with design rationale, and cross-links with previous week documents. Use whenever the user shares EKS study content or drafts — networking, storage, security, autoscaling, or any other EKS topic."
---

# Writing EKS Notes

Workflow:
1. Study content arrives → save to staging file, reply with brief ack
2. User signals done → run Finalize steps below, then write doc using `write-markdown` rules

---

## Setup (runs once per topic)

On the first content message, scan for existing staging files:

```bash
ls docs/drafts/*-staging.md 2>/dev/null
```

If `docs/` does not exist in cwd, ask for the project root path first.

**If staging files exist**, show the list and ask:
- "Continue one of these, or start a new topic?"
- If continuing: use that file's WEEK/TOPIC from the header comments, skip questions
- If starting new: ask for week number and topic slug

**If no staging files exist**, ask:
1. Week number (e.g. `week2`) — determines `docs/week{N}/` output path
2. Topic slug (e.g. `vpc-cni`, `storage`, `autoscaling`) — used in filename

```bash
mkdir -p docs/drafts
cat > docs/drafts/week{N}-{topic}-staging.md << 'EOF'
<!-- WEEK: {N} -->
<!-- TOPIC: {topic} -->
<!-- CREATED: {date} -->
EOF
```

---

## Saving Content

Append each incoming message to the staging file:

```bash
cat >> docs/drafts/week{N}-{topic}-staging.md << 'EOF'

---
{content}
EOF
```

Reply briefly: key topics detected, running total of content accumulated.

---

## Finalize

Run these steps in order when the user signals they are done.

### Step 1 — Analyze staging

```bash
cat docs/drafts/week{N}-{topic}-staging.md
```

Identify across all content:
- Topic groupings and intended section order
- Duplicate explanations to merge
- Concepts without design rationale (need Why explanation)
- Counterintuitive constraints (need blockquote)
- 3+ parallel options (need comparison table or tabs)
- Cross-ref candidates — concepts likely covered in prior weeks

### Step 2 — Cross-reference prior weeks

```bash
find docs/ -name "*.md" ! -path "*/drafts/*" | sort
```

- Concept already covered in a prior week → link + 1–2 sentence recap only
- Current doc deepens a prior topic → open that section with a connecting sentence

### Step 3 — Verify facts + collect image candidates

Validate key claims via AWS Knowledge MCP or `web_fetch`.

Priority: numeric facts (ENI limits, maxPods), daemon behavior (ipamd warm pool),
best practices, deprecated patterns.

Key sources: `docs.aws.amazon.com/eks/latest/best-practices/` and
`docs.aws.amazon.com/eks/latest/userguide/`.

**While fetching each page, collect image candidates from the main content area only**
(exclude navigation, headers, footers, and inline icons).

For each candidate, extract:
- Direct image URL
- Alt text
- 1–2 sentences of surrounding context from the page
- Source page URL

After all pages are fetched, present candidates to the user:

```
IMAGE CANDIDATES
================
[1] Alt: {alt text}
    Context: "{surrounding text}"
    URL: {image url}
    Source: {page title} ({page url})

[2] ...

Which should I include? Reply with numbers, or "none".
```

Wait for the user's reply before proceeding to Step 4.

### Step 4 — Write document

Apply `write-markdown` rules to structure the document.

Path: `docs/week{N}/eks-week{N}-{topic}.md`

Document structure:
```
> Cloudnet@EKS Week{N}

# Introduction
[Opens with the "pain without it" angle — what operators must handle manually
without this feature. Introduces the solution as the answer.]

# Core Concept / Architecture
[Overall structure. Insert selected architecture images here with attribution.]

## Sub-topics
[Detail sections with write-markdown components throughout.]

# Hands-on
[Optional — only when commands meaningfully demonstrate the concept.]
```

Assembly:
- Reorganize by topic, not arrival order
- Merge duplicates identified in Step 1
- Insert selected images with format: `![alt](url)` + `*[Source: title](page-url)*`
- Add `<!-- TODO: screenshot of [...] -->` where visuals would help but none were selected
- Lab scripts go to `labs/week{N}/` — reference with a relative link

### Step 5 — Archive staging

```bash
mv docs/drafts/week{N}-{topic}-staging.md \
   docs/drafts/week{N}-{topic}-$(date +%Y%m%d).archived.md
```

---

## Checklist

- [ ] No content dropped from staging
- [ ] Duplicate concepts merged
- [ ] Facts verified against AWS docs
- [ ] Image candidates presented to user; selected images inserted with attribution
- [ ] Sections without images have TODO placeholders where relevant
- [ ] Counterintuitive decisions have blockquote explanation
- [ ] 3+ options use comparison table or tabs
- [ ] Config keys / env vars use def_list
- [ ] Cross-references to prior weeks; no re-explanation of already-covered concepts
- [ ] Hands-on section included only where meaningful
- [ ] Lab scripts in `labs/week{N}/`, referenced by relative link
- [ ] Staging file archived

---
{content}
EOF
```

Reply briefly: key topics detected, running total of content accumulated.

---

## Finalize

Run these steps in order when the user signals they are done.

### Step 1 — Analyze staging

```bash
cat docs/drafts/week{N}-{topic}-staging.md
```

Identify across all content:
- Topic groupings and intended section order
- Duplicate explanations to merge
- Concepts without design rationale (need Why explanation)
- Counterintuitive constraints (need blockquote)
- 3+ parallel options (need comparison table or tabs)
- Cross-ref candidates — concepts likely covered in prior weeks

### Step 2 — Cross-reference prior weeks

```bash
find docs/ -name "*.md" ! -path "*/drafts/*" | sort
```

- Concept already covered in a prior week → link + 1–2 sentence recap only
- Current doc deepens a prior topic → open that section with a connecting sentence

### Step 3 — Verify facts + collect image candidates

Validate key claims via AWS Knowledge MCP or `web_fetch`.

Priority: numeric facts (ENI limits, maxPods), daemon behavior (ipamd warm pool),
best practices, deprecated patterns.

Key sources: `docs.aws.amazon.com/eks/latest/best-practices/` and
`docs.aws.amazon.com/eks/latest/userguide/`.

**While fetching each page, collect image candidates from the main content area only**
(exclude navigation, headers, footers, and inline icons).

For each candidate, extract:
- Direct image URL
- Alt text
- 1–2 sentences of surrounding context from the page
- Source page URL

After all pages are fetched, present candidates to the user:

```
IMAGE CANDIDATES
================
[1] Alt: {alt text}
    Context: "{surrounding text}"
    URL: {image url}
    Source: {page title} ({page url})

[2] ...

Which should I include? Reply with numbers, or "none".
```

Wait for the user's reply before proceeding to Step 4.

### Step 4 — Write document

Apply `write-markdown` rules to structure the document.

Path: `docs/week{N}/eks-week{N}-{topic}.md`

Document structure:
```
> Cloudnet@EKS Week{N}

# Introduction
[Opens with the "pain without it" angle — what operators must handle manually
without this feature. Introduces the solution as the answer.]

# Core Concept / Architecture
[Overall structure. Insert selected architecture images here with attribution.]

## Sub-topics
[Detail sections with write-markdown components throughout.]

# Hands-on
[Optional — only when commands meaningfully demonstrate the concept.]
```

Assembly:
- Reorganize by topic, not arrival order
- Merge duplicates identified in Step 1
- Insert selected images with format: `![alt](url)` + `*[Source: title](page-url)*`
- Add `<!-- TODO: screenshot of [...] -->` where visuals would help but none were selected
- Lab scripts go to `labs/week{N}/` — reference with a relative link

### Step 5 — Archive staging

```bash
mv docs/drafts/week{N}-{topic}-staging.md \
   docs/drafts/week{N}-{topic}-$(date +%Y%m%d).archived.md
```

---

## Checklist

- [ ] No content dropped from staging
- [ ] Duplicate concepts merged
- [ ] Facts verified against AWS docs
- [ ] Image candidates presented to user; selected images inserted with attribution
- [ ] Sections without images have TODO placeholders where relevant
- [ ] Counterintuitive decisions have blockquote explanation
- [ ] 3+ options use comparison table or tabs
- [ ] Config keys / env vars use def_list
- [ ] Cross-references to prior weeks; no re-explanation of already-covered concepts
- [ ] Hands-on section included only where meaningful
- [ ] Lab scripts in `labs/week{N}/`, referenced by relative link
- [ ] Staging file archived
