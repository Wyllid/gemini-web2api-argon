# Running this fork as a local Windows gateway

This fork of [zinda2000/gemini-web2api-argon](https://github.com/zinda2000/gemini-web2api-argon) is used as a **local, native Windows
service** that serves several Google accounts of one Chrome profile to OpenAI-compatible clients (coding agents).

Lineage: `zexadev/gemini-web2api-go` → `Mag1cFall/Gemini-Web2API` (all of the Chrome/OAuth renewal, multi-account and routing work)
→ `zinda2000/gemini-web2api-argon` (a 2-commit snapshot with a few tweaks) → this fork. The snapshot has no shared git history with
Mag1cFall, so upstream fixes have to be ported by diff, not merged.

## Why this base

| Need | How it is handled here |
|---|---|
| Several accounts from one Chrome profile | One auth state per account with its own `authUser`; every request, the home page, uploads and RPCs go through `/u/N/...` |
| Sessions that die while nobody exports cookies | The server keeps them alive itself: `RotateCookies` every ~10 min, `ListAccounts` to check that the session is still valid, and **automatic renewal** through `OAuthMultilogin` using the account's Chrome refresh token |
| Silent model downgrades / exhausted quota | The model hash in the answer is verified; on mismatch the model is put on cooldown for that account until the usage window resets, and the client gets an honest `429` with the reset time |
| Fair routing | One request slot per account (`PER_ACCOUNT_CONCURRENCY`, default 1), `round-robin` or `fill-first`, per-model cooldowns |

Limits to know about:

- **Renewal only works on the Windows machine where Chrome is signed in.** The refresh token is read from Chrome's profile
  (`Web Data`, App-Bound encryption), so the gateway must run natively on that machine, not in a Linux container.
- The refresh token is stored in `auth/<account>/storage-state.json`. Treat that directory like a password store.
- The upstream code base has **no automated tests** apart from the web UI. This fork adds tests only for the code it changes.
- The snapshot is maintained by one person; Google's web protocol changes break such gateways without notice.

## What this fork changes

- `internal/gemini`: Temporary Chat is restored. The snapshot hard-disabled it, so **every API call created a visible conversation in
  each account's history**, even with `GEMINI_SAVE_HISTORY=false`. The decision now lives in `useTemporaryChat` (guests, opted-in history
  and features that read results back from the conversation — Task, Deep Research, Video — use a regular chat) and has a table test.
  `GEMINI_SAVE_HISTORY=true` brings the snapshot's behavior back (also required to recover an answer after a dropped stream).
- This document.

Measured on one host (Windows 10 x64, Chrome signed in to 9 Google accounts) before restoring Temporary Chat, then again after:
`gemini-4-argon` and `gemini-3.1-pro` answered 5/5 in both modes; `gemini-3.8-flash` was slow and unstable in **both** modes
(35–150 s, 1–2 timeouts out of 5), so the hard-disable was not justified by those results. Prefer Argon / Pro over 3.8 Flash.

## Build (no local Go or Node needed)

```bash
# 1. admin UI (embedded into the binary)
docker run --rm -v "$PWD:/src" -w /src/web node:22-trixie-slim sh -c "corepack enable && pnpm install --frozen-lockfile && pnpm run build"
# 2. Windows binary (console, not the Wails desktop build)
docker run --rm -v "$PWD:/src" -v gomodcache:/go/pkg/mod -w /src golang:1.26 sh -c \
  "go test -tags nomsgpack ./internal/gemini/ && GOOS=windows GOARCH=amd64 CGO_ENABLED=0 go build -tags nomsgpack -trimpath -ldflags='-s -w' -o dist-win/gemini-web2api.exe ./cmd/gemini-web2api"
```

## Set up accounts and run

Work in a directory **outside the repository** (it will hold credentials), copy `gemini-web2api.exe` there and import each account
that is signed in to Chrome. This reads the Chrome profile and briefly starts an isolated temporary Chrome process; open windows are not touched.

```powershell
.\gemini-web2api.exe setup --email "name@example.com"     # repeat for each account (about 5 s each)
```

Create `.env` next to the executable (restart after editing):

```ini
LISTEN_ADDR=127.0.0.1:8007
PROXY_API_KEY=<long random string>
GEMINI_SAVE_HISTORY=false
ROUTING_STRATEGY=round-robin
PER_ACCOUNT_CONCURRENCY=1
```

Start it (`--open-ui=false` for a headless start) and check readiness:

```powershell
.\gemini-web2api.exe --open-ui=false
curl http://127.0.0.1:8007/readyz        # {"accounts":9,"available":9,"status":"ready",...}
curl http://127.0.0.1:8007/v1/models -H "Authorization: Bearer <PROXY_API_KEY>"
```

With `PROXY_API_KEY` set, requests without the key (or with a wrong one) are dropped at the connection level.
Startup at login: see "Windows hidden startup" in the README (registry `Run` entry with `--hidden`).

## Using it from a coding agent (omp example)

```yaml
# ~/.omp/agent/models.yml
providers:
  argon:
    baseUrl: http://127.0.0.1:8007/v1
    api: openai-completions
    auth: apiKey
    apiKey: '!python -c "import re;print(re.search(r''PROXY_API_KEY=(\S+)'',open(r''C:/path/to/run/.env'').read()).group(1))"'
    models:
      - id: gemini-4-argon
        contextWindow: 200000      # large prompts work (464 KB answered correctly in ~54 s) but latency grows with size
        maxTokens: 16384
        supportsTools: true
```

Compact before the context gets huge: a 120k-token prompt took ~54 s, a small tool-call turn 6–40 s.

## Behavior observed

| Check | Result |
|---|---|
| Import 9 accounts from Chrome | all imported, ~5 s each; the free account lists 12 models, the others 19 |
| Argon, 10 sequential requests | 10/10 correct, spread over 7 accounts (round-robin); the exhausted account was skipped |
| Exhausted usage window | `429 rate_limit_exceeded` with the account's own "limit reached, resets at HH:MM" text; that model is cooled down until then |
| Corrupted session cookies (22 cookies overwritten) | detected at startup, renewed in 1.6 s, account ready, cookies rewritten |
| `PROXY_API_KEY` | wrong or missing key → connection reset; correct key → 200 |

Not verified: behavior over many hours (sessions issued by `OAuthMultilogin` last about 2 h and must be renewed repeatedly), and what
happens when Chrome's own sign-in is revoked.

## Operations

- Logs: stdout of the process (`INFO/WARN` lines per request: account chosen, first output, cooldowns, renewals).
- Add or remove accounts in the admin UI (`http://127.0.0.1:8007/`) or with `setup`; restart to pick up new `auth/` directories.
- If an account shows "pending authentication", sign in again in Chrome and re-run `setup --email ...`.
- Never commit `auth/`, `.env` or `data/`.
