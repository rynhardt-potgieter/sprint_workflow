---
name: zod-rjsf-forms
description: "Schema-driven questionnaire engine — Zod as the single source of truth, converted to JSON Schema and rendered with react-jsonschema-form (RJSF). Use this skill when building multi-section data-capture forms (onboarding, tax/compliance questionnaires, declarations), a Zod→JSON-Schema conversion utility, tabbed section layouts, or any form where a schema drives rendering and validation. Covers the cross-tab validation-error-summary rule and the 'A-or-B' schema representability rule."
---

# Zod → JSON Schema → RJSF Forms

Authoritative pattern for schema-driven questionnaires: **Zod is the single source of truth**, converted to JSON Schema, rendered by RJSF, validated the same way on the server. Ideal for capturing structured data through a review-before-submit flow (onboarding wizards, a multi-section tax or compliance questionnaire, regulatory declarations).

## The pipeline
```
Zod schema (one shared package)  ──z.toJSONSchema──►  JSON Schema (draft-7)  ──►  RJSF <Form>  ──►  review  ──►  submit
      (source of truth)              (a small util)          (+ uiSchema)      (validate)   (re-validate server-side)
```

## 1. Author the schema (single source of truth)
Keep schemas in one shared package (e.g. `packages/schemas/src/<area>/<model>.schema.ts`) and barrel every new schema from `src/index.ts`. Use the current Zod API (`z.email()`, not `z.string().email()`).
```ts
import { z } from 'zod'
export const OnboardingSchema = z.object({
  registrationNo: z.string().describe('Company registration number'),
  taxReferenceNo: z.string().describe('Tax reference'),
  financialYearEnd: z.iso.date(),
  isDormant: z.boolean().describe('Entity was dormant for the full period'),
})
export type Onboarding = z.infer<typeof OnboardingSchema>
```
- Use `.describe()` for labels/help — it maps to JSON Schema `description`.
- Build shared primitives once (id, timestamps, jurisdiction-specific ids) under a `common/` folder rather than redeclaring per model.

## 2. Convert to JSON Schema — one tiny util
Modern Zod ships native JSON Schema output; RJSF's AJV8 validator defaults to draft-07:
```ts
import { z } from 'zod'
import type { RJSFSchema } from '@rjsf/utils'

export const zodToRJSFSchema = (schema: z.ZodType): RJSFSchema =>
  z.toJSONSchema(schema, { target: 'draft-7' }) as RJSFSchema
```
Verify enums, optionals, nested objects, and arrays render correctly. The real effort is the **`uiSchema`** (widgets, ordering, help text, section layout) and any custom widgets — not the conversion.

## 3. Render with RJSF
`@rjsf/*` + a validator (`@rjsf/validator-ajv8`). Prefer a shadcn/Base-UI RJSF theme; if none fits, supply `widgets`/`templates` that render your own design-system primitives so forms match the app, not Bootstrap.
```tsx
"use client";
import Form from '@rjsf/core'; // or the chosen themed Form
import validator from '@rjsf/validator-ajv8';

<Form schema={zodToRJSFSchema(OnboardingSchema)} uiSchema={onboardingUiSchema} validator={validator}
      formData={draft} onSubmit={({ formData }) => save(formData)} />
```
- The workflow is **capture → review/verify → submit.** Render a read-only review step before the submit button.
- **Re-validate on submit server-side with the same Zod schema** — never trust client validation alone.

## 4. Tabbed section layout — surface a cross-tab error summary (MANDATORY)
When a multi-section form uses a **tabbed** section layout (e.g. `ui:options.layout: "tabs"`), inactive tab panels are unmounted (Base UI `Tabs.Panel` and most tab primitives unmount inactive children), and forms typically run `showErrorList={false}`. The consequence: **a required field left blank on an inactive tab is invisible.** AJV correctly blocks the submit/advance, but the user sees nothing and cannot tell which tab is incomplete — the button silently no-ops.

Every tabbed RJSF form MUST add an **`onError`** handler that surfaces a cross-tab summary:
```tsx
<Form
  {...props}
  showErrorList={false}
  onError={(errors) => {
    const sections = errors
      .map((e) => sectionTitleForField(e.property))   // map errored field → its section title
      .filter((s, i, a) => s && a.indexOf(s) === i);
    setSummary(sections);                              // → persistent destructive <Alert> naming the sections
    toast.error(`Complete: ${sections.join(', ')}`);   // transient cue
  }}
/>
```
- The summary must be a **persistent** destructive `Alert` naming the incomplete **section titles** (map each errored field to its section via your `sections` config), plus an optional transient toast.
- Do NOT "fix" the no-op by weakening validation, and do NOT swap in RJSF's raw `<ErrorList>` (off-theme). This is the schema-form cousin of the persistent-surface rule in `nextjs-app-router`.

## 5. The "A-or-B" representability rule (regulatory OR-conditions)
When a schema encodes a regulatory "**A OR B**" rule (e.g. "**>5% ownership OR effective control**", or a conditional tax gate), do **not** make the A-branch field required-and-constrained in a way that silently makes every B-branch case unrepresentable.

Concrete trap: making `ownershipPercent` `required + .gt(5)` deletes the *control-based* case (e.g. someone with effective control but 0% shares — a case your own enums and field-list docs model). The fix:
- Make the A-branch field **optional**, keeping its constraint **only when present** (`z.number().gt(5).optional()`).
- Move the "**A or B must hold**" declarability check to **review/submit time** — a documented review-time invariant, exactly like a "1-vs-2 signatories" rule that isn't a Zod refinement.
- Cross-check the schema against its own field-list doc: a field required in the schema but described as *conditional* in the doc is the tell.

## Anti-patterns
- ❌ Redeclaring a form's shape in the API or web instead of importing the one shared schema.
- ❌ Leaving the `zodToRJSFSchema` conversion as a stub.
- ❌ Trusting RJSF/client validation without re-validating server-side.
- ❌ A tabbed form with no cross-tab error summary (silent no-op on submit).
- ❌ A hard `required + constrained` A-branch field that deletes the B-branch of an "A or B" rule.
- ❌ Bootstrap-styled RJSF forms that clash with a shadcn app.
