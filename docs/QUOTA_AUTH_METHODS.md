# ClaudeBar - Claude & Gemini 쿼터 인증 및 조회 방식

> **목적**: 이 문서는 ClaudeBar(Swift/macOS)에서 Claude와 Gemini의 쿼터를 어떻게 인증하고 조회하는지 정리한 레퍼런스입니다.  
> 다른 프로젝트에서 동일한 쿼터 정보를 가져올 때 비교 참고용으로 사용하세요.

---

## 목차

1. [공통 구조](#1-공통-구조)
2. [Claude 인증 방식](#2-claude-인증-방식)
3. [Claude 쿼터 조회 API](#3-claude-쿼터-조회-api)
4. [Gemini 인증 방식](#4-gemini-인증-방식)
5. [Gemini 쿼터 조회 API](#5-gemini-쿼터-조회-api)
6. [에러 처리 및 토큰 갱신](#6-에러-처리-및-토큰-갱신)
7. [크레덴셜 파일 구조](#7-크레덴셜-파일-구조)

---

## 1. 공통 구조

두 프로바이더 모두 **OAuth 2.0 Bearer Token** 방식을 사용합니다.  
각 CLI(`claude login`, `gemini login`)가 저장한 OAuth 토큰을 재사용하는 구조입니다.

```
사용자 로그인 (CLI)
    ↓
OAuth 토큰 저장 (로컬 파일)
    ↓
ClaudeBar / 내 앱이 파일에서 토큰 읽기
    ↓
각 회사 내부 API에 Bearer 토큰으로 쿼터 요청
    ↓
JSON 응답 파싱 → 화면 표시
```

---

## 2. Claude 인증 방식

### 크레덴셜 로드 우선순위 (3단계)

| 순위 | 소스 | 경로/방법 | 스코프 |
|------|------|-----------|--------|
| 1 | **파일** | `~/.claude/.credentials.json` | Full-scope (`claude login`으로 저장) |
| 2 | **Keychain** | Service: `"Claude Code-credentials"` | Full-scope |
| 3 | **환경변수** | `CLAUDE_CODE_OAUTH_TOKEN` | Inference-only (`claude setup-token`) |

> ⚠️ **중요**: 쿼터 조회는 Full-scope 토큰이 필요합니다.  
> `CLAUDE_CODE_OAUTH_TOKEN` (inference-only)으로는 `/api/oauth/usage` 호출이 불가할 수 있습니다.

### 토큰 만료 체크 로직

```
만료 시간(expiresAt, ms) - 현재 시간(ms) < 5분(300,000ms)
    → 갱신 필요로 판단
```

### OAuth 토큰 갱신 (Refresh)

```
POST https://platform.claude.com/v1/oauth/token
Content-Type: application/json

{
  "grant_type": "refresh_token",
  "refresh_token": "<refresh_token>",
  "client_id": "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
}
```

> `client_id`는 Claude Code CLI의 공식 client_id입니다.

---

## 3. Claude 쿼터 조회 API

### 방식 A: REST API (권장)

```
GET https://api.anthropic.com/api/oauth/usage

Headers:
  Authorization: Bearer <access_token>
  Accept: application/json
  Content-Type: application/json
  anthropic-beta: oauth-2025-04-20
  User-Agent: ClaudeBar
```

### 응답 구조

```json
{
  "five_hour": {
    "utilization": 25.5,
    "resets_at": "2026-01-15T03:30:00Z"
  },
  "seven_day": {
    "utilization": 35.0,
    "resets_at": "2026-01-22T00:00:00Z"
  },
  "seven_day_sonnet": {
    "utilization": 10.0,
    "resets_at": "2026-01-22T00:00:00Z"
  },
  "seven_day_opus": {
    "utilization": 50.0,
    "resets_at": "2026-01-22T00:00:00Z"
  },
  "extra_usage": {
    "is_enabled": true,
    "used_credits": 541,
    "monthly_limit": 2000
  }
}
```

> `percentRemaining = 100.0 - utilization`  
> `used_credits`는 센트(cent) 단위 → 달러 변환: `cents / 100`

### Rate Limit

- 1시간 창(window) 기반 제한 존재
- `Retry-After` 헤더 파싱 → 기본 5분 백오프
- ClaudeBar는 **15분 캐시 TTL** 적용 (불필요한 재호출 방지)

### 방식 B: CLI 파싱 (폴백)

```bash
# 작업 디렉토리: ~/.config/ClaudeBar/Probe/
claude /usage
```

- **ANSI 코드 제거** 후 텍스트 파싱 (SwiftTerm 라이브러리 사용)
- 정규식: `([0-9]{1,3}) % (used|left)`
- `"25% used"` → `remainingPercent = 75.0`
- 리셋 시간: 상대값(`"2h 15m"`) 또는 절대값(`"Jan 15, 3:30pm"`) 모두 파싱

### 프로브 모드 폴백 로직

```
기본 프로브 시도 (API 또는 CLI)
    ↓ 실패 시 (Rate Limit 제외)
반대 프로브로 자동 전환
    ↓ Rate Limit 오류
즉시 오류 반환 (폴백 없음)
```

---

## 4. Gemini 인증 방식

### 크레덴셜 파일

```
~/.gemini/oauth_creds.json
```

### 파일 구조

```json
{
  "access_token": "ya29.xxxxx",
  "refresh_token": "1//xxxxx",
  "expiry_date": 1748123456789
}
```

> `expiry_date`는 **밀리초(ms)** 단위 Unix timestamp

### HTTP 요청 헤더

```
Authorization: Bearer <access_token>
Content-Type: application/json
```

### 토큰 갱신 방식 (별도 Refresh API 없음)

Gemini는 자체 refresh endpoint 대신 **CLI를 통한 갱신**을 사용합니다:

```
API 호출 → 401 응답
    ↓
gemini CLI를 잠깐 실행:
  echo "/quit" | gemini
  (CLI 시작 시 자동으로 OAuth 토큰 갱신)
    ↓
1.5초 대기
    ↓
API 재호출 (1회만 재시도)
    ↓
재시도도 실패 시 → authenticationRequired 오류
```

---

## 5. Gemini 쿼터 조회 API

### 엔드포인트

```
POST https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota
Content-Type: application/json
Authorization: Bearer <access_token>

Body:
{
  "project": "<gcp_project_id>"
}
```

> `project`는 GCP 프로젝트 ID (없어도 동작하나, 조직 계정은 있어야 정확한 쿼터 반환)

### 응답 구조

```json
{
  "buckets": [
    {
      "modelId": "gemini-2.5-pro",
      "remainingFraction": 0.855,
      "resetTime": "2026-01-15T03:30:00Z",
      "tokenType": "standard"
    },
    {
      "modelId": "gemini-2.5-flash",
      "remainingFraction": 0.432,
      "resetTime": "2026-01-15T03:30:00Z",
      "tokenType": "standard"
    },
    {
      "modelId": "gemini-3-pro-preview",
      "remainingFraction": 0.855,
      "resetTime": "2026-01-15T03:30:00Z",
      "tokenType": "standard"
    }
  ]
}
```

> `remainingFraction`: 0.0 ~ 1.0 범위 (1.0 = 100% 남음)  
> `resetTime`: ISO 8601 형식

### 모델 별칭(Alias) 중복 제거

동일한 쿼터를 여러 모델 ID가 공유하는 문제가 있습니다:

| 티어 | 공유하는 모델 ID들 |
|------|-------------------|
| Pro | `gemini-2.5-pro`, `gemini-3-pro-preview`, `gemini-3.1-pro-preview` |
| Flash | `gemini-2.5-flash`, `gemini-3-flash-preview` |

**중복 제거 전략**:
1. 모델 ID에서 티어 추출 (`"pro"`, `"flash"`, `"flash-lite"`)
2. 같은 티어끼리 그룹화
3. 버전 번호가 가장 높은 비-preview 모델을 대표로 선택
4. 화면 표시: `"Pro"`, `"Flash"`, `"Flash Lite"` (모델 ID 대신 티어 라벨 사용)

---

## 6. 에러 처리 및 토큰 갱신

### Claude 에러 코드별 처리

| 에러 | 원인 | 처리 방법 |
|------|------|-----------|
| `401 / 403` | 토큰 만료 또는 무효 | refresh_token으로 갱신 후 재시도 (1회) |
| `401` + no refresh_token | setup-token (inference-only) | 즉시 authRequired 오류 |
| `429` | Rate Limit | `Retry-After` 헤더 파싱, 기본 5분 대기 |
| `invalid_grant` | 세션 만료 | 사용자 재로그인 필요 |

### Gemini 에러 코드별 처리

| 에러 | 원인 | 처리 방법 |
|------|------|-----------|
| `401` | 토큰 만료 | CLI 실행으로 토큰 갱신 후 재시도 (1회) |
| `401` (재시도 후도 실패) | 완전 만료 | authRequired 오류 반환 |
| 크레덴셜 파일 없음 | 미로그인 | authRequired 오류 반환 |

---

## 7. 크레덴셜 파일 구조

### Claude: `~/.claude/.credentials.json`

```json
{
  "claudeAiOauth": {
    "accessToken": "sk-ant-ocp05-...",
    "refreshToken": "sk-ant-orc05-...",
    "expiresAt": 1748123456789.0,
    "subscriptionType": "claude_pro"
  }
}
```

> `expiresAt`: **밀리초(ms)** 단위 Unix timestamp  
> `subscriptionType`: `"claude_pro"` | `"claude_max"` | `"claude_api"` 등

### Gemini: `~/.gemini/oauth_creds.json`

```json
{
  "access_token": "ya29.a0AfH6SM...",
  "refresh_token": "1//0gxxxxxxx",
  "expiry_date": 1748123456789
}
```

> `expiry_date`: **밀리초(ms)** 단위 Unix timestamp

---

## 요약 비교표

| 항목 | Claude | Gemini |
|------|--------|--------|
| **인증 방식** | OAuth 2.0 Bearer | OAuth 2.0 Bearer |
| **크레덴셜 위치** | `~/.claude/.credentials.json` | `~/.gemini/oauth_creds.json` |
| **Keychain 지원** | ✅ (`Claude Code-credentials`) | ❌ |
| **환경변수 지원** | ✅ (`CLAUDE_CODE_OAUTH_TOKEN`) | ❌ |
| **토큰 갱신** | 자체 Refresh API (`/v1/oauth/token`) | CLI 실행으로 갱신 |
| **쿼터 API** | `api.anthropic.com/api/oauth/usage` | `cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota` |
| **쿼터 단위** | `utilization` (0~100%) | `remainingFraction` (0.0~1.0) |
| **리셋 시간 형식** | ISO 8601 (`resets_at`) | ISO 8601 (`resetTime`) |
| **Rate Limit** | 1시간 창, `Retry-After` 헤더 | 알려진 제한 없음 |
| **캐시 전략** | 15분 TTL | 없음 (매번 호출) |
| **필수 헤더** | `anthropic-beta: oauth-2025-04-20` | 없음 |
| **프로젝트 ID** | 불필요 | Body에 포함 (조직 계정용) |

---

*이 문서는 ClaudeBar 소스코드 (`Sources/Infrastructure/Claude/`, `Sources/Infrastructure/Gemini/`) 분석을 기반으로 작성되었습니다.*
