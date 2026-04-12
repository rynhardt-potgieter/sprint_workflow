---
name: security-compliance
description: "Security and compliance standards — Auth0 JWT integration, OWASP Top 10 mitigations, PCI DSS 4.0, PII/POPIA data protection, encryption at rest and in transit, secrets management, and audit trails. Use this skill when implementing authentication, handling sensitive data, storing PII, processing payments, reviewing security posture, or ensuring regulatory compliance. MUST use for any code touching user data, financial data, or authentication flows."
---

# Security & Compliance Standards

This skill defines mandatory security and compliance patterns. Violations of these patterns are blocking issues in code review.

## Auth0 Integration

### Backend (ASP.NET Core)
```csharp
builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        options.Authority = $"https://{config["Auth0:Domain"]}/";
        options.Audience = config["Auth0:Audience"];
        options.MapInboundClaims = false;  // CRITICAL: preserves "sub", "email" claim names
        options.NameClaimType = "sub";
    });
```

**CRITICAL**: `MapInboundClaims = false` prevents ASP.NET from remapping JWT claims to XML namespace URIs. Without this, `User.FindFirst("sub")` returns null.

### Claims Extraction
```csharp
private string CurrentUserId => User.FindFirst("sub")?.Value
    ?? throw new UnauthorizedAccessException("No sub claim");
private string? UserEmail => User.FindFirst("email")?.Value;
```

### Frontend (Auth0 React SDK)
```tsx
// Token accessor for API client
const { getAccessTokenSilently } = useAuth0()
setTokenAccessor(() => getAccessTokenSilently())
```

- Tokens stored in memory only — NEVER localStorage or sessionStorage
- Use Auth0's built-in refresh token rotation
- AuthGate component handles login redirect + user provisioning

### Token Best Practices
- Access tokens: Short-lived (5-15 min), stored in memory
- Refresh tokens: HttpOnly cookie or Auth0 SDK rotation
- ID tokens: Never sent to APIs — use access tokens
- For BFF pattern: Backend holds tokens, frontend uses session cookies

## OWASP Top 10 Mitigations

### 1. Injection (SQL, NoSQL, Command)
- Use parameterized queries (EF Core does this by default)
- Never concatenate user input into SQL: `$"SELECT * FROM users WHERE id = '{id}'"` is FORBIDDEN
- Dapper: Always use `@param` parameters, never string interpolation

### 2. Broken Authentication
- Auth0 handles password hashing, MFA, brute-force protection
- Implement account lockout for custom auth flows
- Never log tokens or passwords

### 3. Sensitive Data Exposure
- TLS everywhere (enforced at infrastructure level)
- Encrypt PII at rest (see PII section below)
- Never return sensitive fields in API responses (passwords, tokens, full ID numbers)

### 4. XXE (XML External Entities)
- Don't parse XML from user input; use JSON exclusively

### 5. Broken Access Control
- `[Authorize]` at controller level, `[AllowAnonymous]` per-method only when justified
- Always filter by `CurrentUserId` or `TenantId` in queries — never trust client-provided IDs
- Check ownership: `if (goal.UserId != CurrentUserId) return Forbid();`

### 6. Security Misconfiguration
- Remove Swagger in production: `if (app.Environment.IsDevelopment()) app.UseSwagger();`
- Set security headers (CSP, X-Frame-Options, HSTS)
- Never expose stack traces in production error responses

### 7. XSS (Cross-Site Scripting)
- React auto-escapes JSX by default — never use `dangerouslySetInnerHTML`
- Sanitize markdown rendering if accepting user-generated content
- CSP headers: `Content-Security-Policy: default-src 'self'`

### 8. Insecure Deserialization
- Use `System.Text.Json` with strict type handling
- Never deserialize untrusted data into arbitrary types

### 9. Insufficient Logging
- Log authentication events (login, logout, failed attempts)
- Log authorization failures
- Log data access patterns for sensitive resources
- NEVER log tokens, passwords, or PII

### 10. SSRF (Server-Side Request Forgery)
- Validate and allowlist URLs before making backend HTTP calls
- Never let user input control entire URLs for backend fetches

## PII / Data Protection Compliance

### What is PII in Our Systems
| Field | Classification | Treatment |
|-------|---------------|-----------|
| Email | PII | Encrypt at rest, mask in logs |
| Phone | PII | Encrypt at rest, mask in logs |
| Full Name | PII | Encrypt at rest |
| ID/Passport Number | Sensitive PII | Encrypt at rest, never log, mask in UI |
| Tax ID (TIN) | Sensitive PII | Encrypt at rest, never log, mask in UI |
| Date of Birth | PII | Encrypt at rest |
| Address | PII | Encrypt at rest |
| Bank Account | Financial PII | Encrypt at rest, never log, mask in UI |
| Income/Net Worth | Financial PII | Encrypt at rest |

### Data Protection Requirements
1. **Explicit consent**: Collect only with clear, specific consent
2. **Purpose limitation**: Use PII only for the stated purpose
3. **Data minimization**: Collect only what's needed
4. **Breach notification**: Report compromises to the relevant authority promptly
5. **Right to erasure**: Users can request complete deletion of their PII
6. **Accountability**: Organization must have a designated data protection officer/role

### Implementation Patterns

#### Encryption at Rest
```csharp
// Use ASP.NET Core Data Protection for column-level encryption
public class EncryptedStringConverter : ValueConverter<string, string>
{
    public EncryptedStringConverter(IDataProtector protector)
        : base(v => protector.Protect(v), v => protector.Unprotect(v)) { }
}
```

#### Masking in Logs
```csharp
// NEVER log PII directly
_logger.LogInformation("User {UserId} updated profile", userId);  // OK
_logger.LogInformation("User {Email} logged in", email);  // FORBIDDEN
```

#### Masking in UI
```typescript
// Show only last 4 digits of ID numbers
function maskId(id: string): string {
  return '\u2022'.repeat(id.length - 4) + id.slice(-4)
}
```

#### Right to Erasure
```csharp
public async Task EraseUserDataAsync(Guid userId, CancellationToken ct)
{
    // Cascade delete all PII — keep only anonymized transaction records
    var user = await _db.Users.Include(u => u.Profile).FirstAsync(u => u.Id == userId, ct);
    user.Email = $"deleted_{userId}@erased.local";
    user.Profile.FirstName = "Deleted";
    user.Profile.LastName = "User";
    user.Profile.Phone = null;
    // ... scrub all PII fields
    await _db.SaveChangesAsync(ct);
}
```

## PCI DSS 4.0 (Payment Card Data)

### Scope Reduction
- **NEVER store card numbers (PAN)** — use payment processor tokenization (e.g., Stripe)
- Use hosted payment forms (Stripe Elements, processor ACH forms) to keep card data off our servers
- If PAN must transit our backend: encrypt immediately, log only last 4 digits

### Requirements
- TLS 1.2+ for all cardholder data in transit
- Strong cryptography for stored cardholder data (AES-256)
- Unique user IDs for system access
- Restrict access to cardholder data on a need-to-know basis
- Log and monitor all access to cardholder data
- Regular vulnerability scans

### Our Approach
Use third-party payment processors (e.g., Stripe) that handle PCI compliance. Our responsibility is:
1. Never store raw card data
2. Use tokenized references only
3. Secure API keys for payment services
4. Log payment events (amounts, status) without card details

## Secrets Management

### Rules
- **Environment variables** for all secrets — never in code or config files
- `.env` files: NEVER committed, listed in `.gitignore`
- API keys: Backend only — NEVER in frontend code
- Auth0 client secrets: Backend only
- Database passwords: Environment variables
- Third-party API keys: Backend only, use appropriate auth scheme (e.g., HTTP Basic, Bearer)

### Configuration Pattern
```csharp
// appsettings.json — structure only, no values
"ExternalService": {
  "ApiKey": "",    // Set via EXTERNALSERVICE__APIKEY env var
  "ApiSecret": ""  // Set via EXTERNALSERVICE__APISECRET env var
}
```

### Deployment
- Secrets set as platform-specific service variables (e.g., Railway, Azure, AWS)
- Never in Dockerfiles or docker-compose.yml production configs
- Use platform-native reference variables for cross-service secrets

## Audit Trail

For sensitive operations, log:
```csharp
public record AuditEntry(
    string Action,      // "user.profile.updated", "goal.created", "deposit.initiated"
    string UserId,
    string ResourceType,
    string ResourceId,
    DateTimeOffset Timestamp,
    Dictionary<string, object?> Metadata  // Changed fields, but NO PII values
);
```

- Log WHO did WHAT to WHICH resource, WHEN
- Never log the actual PII values in audit entries
- Retain audit logs per regulatory requirements
