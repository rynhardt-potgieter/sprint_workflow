---
name: pulumi-aws
description: "Pulumi (AWS) infrastructure-as-code standards — the add-model table/SSM 'sentinel' scaffolding pattern, resource naming and tagging conventions, the SSM parameter contract between infra and the runtime, stack/config layout, and a LocalStack-compatible provider. Use this skill when adding or reviewing Pulumi/TypeScript AWS infrastructure (S3, DynamoDB, SSM, and related stateful resources)."
---

# Pulumi AWS Infrastructure Standards

Authoritative patterns for a Pulumi/TypeScript AWS stack that owns the **stateful** resources (S3, DynamoDB, SSM, and optionally an auth user pool). The API Gateway + Lambda + IAM typically come from the API's `serverless.yml`; Pulumi owns the durable infrastructure.

## Provider & config
- One `aws.Provider` pinned to a chosen region, wired for LocalStack (`s3UsePathStyle`, endpoint overrides for dynamodb/ssm/s3, and `skip*` flags driven from stack config). Pass `{ provider }` to every resource.
- Choose a state backend explicitly and record the decision (`Pulumi.yaml`): a committed local file backend (`backend: url: file://.`) is a valid choice that needs no `pulumi login` — if you use it, the state dir is tracked in git; do not gitignore it. Otherwise a cloud/S3 backend. Don't mix the two.
- Stack configs: one real-cloud stack (`Pulumi.<env>.yaml`, creds from the AWS chain) and one LocalStack stack (`Pulumi.local.yaml` — `skip*` = true, dummy creds, `aws:endpoints` → `http://localhost:4566`). Start LocalStack (`docker compose up -d`) before `pulumi up` on the local stack. Add a `Pulumi.<stack>.yaml` for any new stack.

## Resource conventions — copy the existing pattern
Every resource follows one naming + tagging shape. Name resources `<app>-<stack>-<model>` and tag them consistently:
```ts
const stack = pulumi.getStack();
const table = new aws.dynamodb.Table(
  `<app>-${stack}-record`,
  {
    billingMode: "PAY_PER_REQUEST",
    hashKey: "pk",
    rangeKey: "sk",
    attributes: [ { name: "pk", type: "S" }, { name: "sk", type: "S" } ],
    tags: { Environment: stack, Project: "<app>", Unit: "infra" },
  },
  { provider },
);
```

## The add-model sentinels (do NOT remove)
A scaffolding step (a codegen CLI or hand-editing) inserts resources at fixed marker comments in the IaC entry file. Keep them intact:
- `// <add-model:tables>` → an `aws.dynamodb.Table` (as above).
- `// <add-model:ssm>`    → an `aws.ssm.Parameter` publishing that table's name.

## The SSM contract (how infra talks to the runtime)
Publish every resource name (table names, bucket names) to **SSM** so the runtime resolves it without hardcoding:
```ts
new aws.ssm.Parameter(
  `<app>-${stack}-record-param`,
  {
    name: `/<app>/${stack}/infra/record-table-name`,
    type: "String",
    value: table.name,
    tags: { Environment: stack, Unit: "infra" },
  },
  { provider },
);
export const recordTable = table.name;   // also a stack output
```
- **Path convention:** `/<app>/{stack}/{unit}/{resource}`. The runtime reads these via a parameter provider (see `dynamodb-single-table` and `serverless-lambda-api`).
- Also `export const` each resource name/ARN needed downstream as a stack output.

## Provisioning an auth user pool (when auth is in scope)
If the app needs an auth user pool (e.g. Cognito) and it isn't provided externally, provision it here: the user pool (email sign-in, a password policy matching the app's client-side rules), an app client (SPA client, no secret, SRP auth), and publish the pool id + client id to SSM (and as stack outputs) so web/env wiring can read them. This is also what makes an API Gateway authorizer real. If the pool is supplied externally, don't re-provision it — read its ids from config/SSM instead.

## Security / cleanliness for review
- Scope IAM to specific resource ARNs and actions when practical — avoid `service:*` on `*`.
- Keep secrets out of the IaC source — use stack config (`config.getSecret`) or an SSM SecureString, never literals. Run a secret scanner pre-commit.
- Export the ids/ARNs downstream consumers need as stack outputs.

## Verification
```bash
pnpm --filter <infra-pkg> check-types
pnpm --filter <infra-pkg> lint
# preview against a stack (needs creds/backend): pulumi preview --stack <env>
```
