export const meta = {
  name: 'arch-review-board',
  description: 'Multi-agent architecture review board — independent expert reviews, challenge round, synthesis',
  phases: [
    { title: 'Independent Review', detail: '5 experts analyze from different dimensions' },
    { title: 'Challenge & Debate', detail: 'Skeptic finds blind spots and contradictions' },
    { title: 'Synthesis', detail: 'Chief Architect produces final report' },
  ],
}

const question = args.question || 'No question provided.'
const context = args.context || 'No additional context.'
const candidateOptions = args.options || ''

const OPTIONS_SECTION = candidateOptions
  ? `\n## Candidate Options\n${candidateOptions}`
  : ''

// ── Phase 1: Independent Expert Reviews ──────────────────────────
phase('Independent Review')

const dimensions = [
  {
    key: 'architecture',
    role: 'Senior Software Architect (15+ years)',
    focus: 'Architecture patterns, coupling vs cohesion, SOLID principles, extensibility, design patterns, layer separation, dependency direction. Evaluate whether the architecture will age gracefully.',
    prompt: `You are a Senior Software Architect with 15+ years of experience across multiple tech stacks. You've seen architectures that scaled beautifully and ones that became nightmares.

## Decision to Review
${question}
${OPTIONS_SECTION}

## Context / Constraints
${context}

## Your Dimension: Architecture & Design Quality
Focus on: architecture patterns, coupling vs cohesion, SOLID principles, extensibility, design patterns, layer separation, dependency direction. Evaluate whether the architecture will age gracefully.

## Instructions
1. Score this dimension (1-10), where 1 = "fundamentally broken" and 10 = "exemplary, will age gracefully"
2. Identify at least 2 specific architectural risks
3. If multiple options are presented, compare them architecturally
4. Note any missing architectural context that would change your assessment
5. Be opinionated — vague "it depends" answers are not useful

## Output Format (MUST use exactly this structure):

### ARCHITECTURE REVIEW (Score: X/10)

**One-Line Verdict**: [Single sentence summary]

**Strengths**:
- ...

**Risks**:
- ...

**Architectural Comparison** (if multiple options):
| Criterion | Option A | Option B | ... |
|-----------|----------|----------|-----|

**Recommendations**:
- ...

**Missing Context That Would Change My Assessment**:
- ...`,
  },
  {
    key: 'performance',
    role: 'Senior Performance Engineer (15+ years)',
    focus: 'Latency, throughput, bottlenecks, resource consumption (CPU/memory/IO), caching strategy, scaling characteristics (vertical vs horizontal), data access patterns, cold start, connection pooling.',
    prompt: `You are a Senior Performance Engineer with 15+ years of experience optimizing systems at scale.

## Decision to Review
${question}
${OPTIONS_SECTION}

## Context / Constraints
${context}

## Your Dimension: Performance & Scalability
Focus on: latency, throughput, bottlenecks, resource consumption, caching, scaling characteristics, data access patterns.

## Instructions
1. Score this dimension (1-10), where 1 = "will collapse under load" and 10 = "performance-optimal design"
2. Identify at least 2 specific performance risks or bottlenecks
3. Estimate rough scalability ceiling (e.g., "this will work until ~X concurrent users")
4. Note performance assumptions that need empirical validation
5. Be specific about WHERE the performance issues would manifest

## Output Format (MUST use exactly this structure):

### PERFORMANCE REVIEW (Score: X/10)

**One-Line Verdict**: [Single sentence summary]

**Strengths**:
- ...

**Risks & Bottlenecks**:
- ...

**Scalability Ceiling Estimate**: ...

**Assumptions That Need Testing**:
- ...

**Recommendations**:
- ...`,
  },
  {
    key: 'security',
    role: 'Senior Security Engineer (15+ years)',
    focus: 'Attack surface, threat modeling, data safety (at rest + in transit), authentication/authorization, injection risks, least privilege, defense in depth, supply chain, error info leakage, audit trail.',
    prompt: `You are a Senior Security Engineer with 15+ years of experience in application security and threat modeling.

## Decision to Review
${question}
${OPTIONS_SECTION}

## Context / Constraints
${context}

## Your Dimension: Security & Reliability
Focus on: attack surface, data safety, authentication/authorization, injection risks, least privilege, defense in depth, error handling safety.

## Instructions
1. Score this dimension (1-10), where 1 = "catastrophic security gaps" and 10 = "defense in depth, secure by default"
2. Identify at least 2 specific security concerns
3. Consider the STRIDE threat model (Spoofing, Tampering, Repudiation, Info disclosure, DoS, Elevation)
4. Flag any "security by obscurity" or "we'll secure it later" red flags
5. Assess reliability/resilience alongside security (they're often intertwined)

## Output Format (MUST use exactly this structure):

### SECURITY REVIEW (Score: X/10)

**One-Line Verdict**: [Single sentence summary]

**Strengths**:
- ...

**Threats & Vulnerabilities**:
- ...

**STRIDE Coverage**:
| Threat | Addressed? | Gap |
|--------|-----------|-----|

**Recommendations**:
- ...

**Critical Security Assumptions**:
- ...`,
  },
  {
    key: 'maintainability',
    role: 'Senior Developer Experience & Maintainability Expert (15+ years)',
    focus: 'Code clarity, testing strategy (unit/integration/e2e), onboarding friction, documentation needs, refactoring risk, debugging ergonomics, cognitive load, "bus factor", tooling quality.',
    prompt: `You are a Senior Developer Experience & Maintainability Expert with 15+ years of experience. You care deeply about whether code is a joy or a burden to work with.

## Decision to Review
${question}
${OPTIONS_SECTION}

## Context / Constraints
${context}

## Your Dimension: Maintainability & Testability
Focus on: code clarity, testing strategy, onboarding friction, documentation needs, refactoring risk, debugging ergonomics, cognitive load.

## Instructions
1. Score this dimension (1-10), where 1 = "will be a maintenance nightmare" and 10 = "clean, testable, well-documented"
2. Identify at least 2 specific maintainability concerns
3. Assess testability: can critical paths be tested without complex mocking?
4. Estimate onboarding cost for a new team member (low/medium/high)
5. Consider long-term cost of ownership beyond initial implementation

## Output Format (MUST use exactly this structure):

### MAINTAINABILITY REVIEW (Score: X/10)

**One-Line Verdict**: [Single sentence summary]

**Strengths**:
- ...

**Concerns**:
- ...

**Testability Assessment**: ...

**Onboarding Cost**: Low / Medium / High — [why]

**Recommendations**:
- ...

**What Will Frustrate Developers in 6 Months**:
- ...`,
  },
  {
    key: 'pragmatism',
    role: 'CTO / Technical Decision Maker (15+ years)',
    focus: 'Timeline feasibility, complexity budget, ROI analysis, build-vs-buy, over-engineering detection, team capability match, opportunity cost, migration path, exit strategy.',
    prompt: `You are a seasoned CTO who has made hundreds of technical decisions — some great, some costly. You balance idealism with cold reality.

## Decision to Review
${question}
${OPTIONS_SECTION}

## Context / Constraints
${context}

## Your Dimension: Pragmatism & Cost-Effectiveness
Focus on: timeline feasibility, complexity budget, ROI, build-vs-buy, over-engineering risk, team capability fit, opportunity cost.

## Instructions
1. Score this dimension (1-10), where 1 = "disaster waiting to happen" and 10 = "perfectly calibrated to reality"
2. Identify if this is over-engineered or under-engineered for the stated context
3. Evaluate ROI: is the complexity justified by the value?
4. Flag any "resume-driven development" (shiny tech chosen for career, not product need)
5. Consider: what's the SIMPLEST thing that could work?

## Output Format (MUST use exactly this structure):

### PRAGMATISM REVIEW (Score: X/10)

**One-Line Verdict**: [Single sentence summary]

**Over/Under Engineering Assessment**: ...

**ROI Analysis**: ...

**Simplest Viable Alternative**: ...

**Risk of Analysis Paralysis**: Low / Medium / High

**Recommendations**:
- ...

**What I'd Tell the CEO** (one sentence): ...`,
  },
]

const reviews = await parallel(
  dimensions.map(d => () =>
    agent(d.prompt, {
      label: d.key,
      phase: 'Independent Review',
    })
  )
)

// Build reviews text for downstream phases, filtering nulls
const reviewTexts = reviews.map((text, i) => {
  if (!text) return `### ${dimensions[i].key.toUpperCase()} REVIEW\n*Review unavailable — agent did not complete.*`
  return text
})

const allReviewsSection = reviewTexts
  .map((t, i) => `## Review ${i + 1}: ${dimensions[i].role}\n\n${t}`)
  .join('\n\n---\n\n')

const summaryTable = dimensions.map((d, i) => {
  const text = reviews[i] || ''
  const scoreMatch = text.match(/Score:\s*(\d+)\/10/i)
  const verdictMatch = text.match(/\*\*One-Line Verdict\*\*:\s*(.+)/i)
  return `| ${d.role.split('(')[0].trim()} | ${scoreMatch ? scoreMatch[1] + '/10' : 'N/A'} | ${verdictMatch ? verdictMatch[1] : 'N/A'} |`
}).join('\n')

// ── Phase 2: Challenge & Debate ──────────────────────────────────
phase('Challenge & Debate')

const challengePrompt = `You are a skeptical, rigorous technical reviewer known for finding flaws that expert panels miss. You are NOT a consensus-builder — your job is to be the constructive contrarian.

## Original Question
${question}
${OPTIONS_SECTION}

## Expert Reviews
${allReviewsSection}

## Instructions
1. **Blind Spots**: What important aspects did ALL reviews miss or barely mention? Look for the elephant in the room.
2. **Contradictions**: Where do reviews disagree? These are decision-critical — the truth is often in the tension.
3. **Questionable Assumptions**: What assumptions are reviewers making that might not hold? Challenge each.
4. **Overconfidence Detection**: Where are reviewers too certain without evidence?
5. **Single Most Critical Concern**: If the decision maker reads only ONE thing from your challenge, what should it be?

Be harsh but fair. Don't manufacture controversy — if the reviews are genuinely aligned, say so.

## Output Format (MUST use exactly this structure):

### CHALLENGE REPORT

**Blind Spots**:
- [Blind spot 1]: why it matters
- ...

**Contradictions Between Reviews**:
- [Topic]: Review X says A, Review Y says B. Resolution: ...

**Questionable Assumptions**:
- [Assumption]: why it might not hold
- ...

**Overconfidence Flags**:
- ...

**Single Most Critical Concern**:
[One paragraph that the decision maker MUST read]

**Revised Risk Level After Challenge**: 🟢 LOW / 🟡 MEDIUM / 🟠 HIGH / 🔴 CRITICAL`

const challenge = await agent(challengePrompt, {
  label: 'challenger',
  phase: 'Challenge & Debate',
})

// ── Phase 3: Synthesis ───────────────────────────────────────────
phase('Synthesis')

const synthesisPrompt = `You are a Chief Architect presenting to the CEO. You must synthesize a multi-expert architecture review board's findings into a clear, actionable decision report.

## Original Question
${question}
${OPTIONS_SECTION}

## Context / Constraints
${context}

## Expert Review Summary
${summaryTable}

## Full Expert Reviews
${allReviewsSection}

## Challenge Report
${challenge || '*No challenges raised.*'}

## Instructions
Produce a comprehensive, decision-oriented report. Follow the template EXACTLY.

Key rules:
- Be decisive — the reader needs a recommendation, not just analysis
- Be honest about uncertainty — if the board is split, say so
- Make trade-offs explicit — every architecture decision is a trade-off
- Include dissenting opinions — don't manufacture consensus
- Keep the executive summary to 3-5 sentences

Use the following template verbatim:

# 🏛️ Architecture Review Board Report

## Executive Summary
[3-5 sentences: what was reviewed, primary recommendation, key trade-off]

## Decision Matrix
| Dimension | Score | Key Concern |
|-----------|-------|-------------|
${dimensions.map((d, i) => {
  const text = reviews[i] || ''
  const scoreMatch = text.match(/Score:\s*(\d+)\/10/i)
  const concernMatch = text.match(/\*\*One-Line Verdict\*\*:\s*(.+)/i)
  return `| ${d.role.split('(')[0].trim()} | ${scoreMatch ? scoreMatch[1] + '/10' : 'N/A'} | ${concernMatch ? concernMatch[1] : 'N/A'} |`
}).join('\n')}

**Overall Risk Level**: [🟢 LOW / 🟡 MEDIUM / 🟠 HIGH / 🔴 CRITICAL — with reasoning]

## Recommendations

### Primary Recommendation
[The recommended approach with clear justification]

### Alternative Considered
[The runner-up — why it was NOT chosen]

### If You Must Do the Opposite
[If the primary recommendation is rejected, what's the safest alternative path?]

## Risk Mitigation Plan
| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| ... | High/Med/Low | High/Med/Low | ... |
| ... | High/Med/Low | High/Med/Low | ... |
| ... | High/Med/Low | High/Med/Low | ... |

## Key Trade-offs
- **Trade-off 1**: [What you gain] vs [What you give up]
- **Trade-off 2**: ...
- **Trade-off 3**: ...

## Action Items
1. [ ] [Immediate action — next 24 hours]
2. [ ] [Short-term action — this week]
3. [ ] [Medium-term action — this sprint/month]
4. [ ] [Validation action — spike/prototype to de-risk]

## Dissenting Opinions
[If any expert significantly disagreed with the consensus, document it here. Minority reports matter.]

## Assumptions That Must Hold
[The top 3 assumptions this recommendation depends on. If any of these are wrong, reconsider.]

---
*Report generated by Architecture Review Board*`

const finalReport = await agent(synthesisPrompt, {
  label: 'synthesis',
  phase: 'Synthesis',
})

return finalReport
