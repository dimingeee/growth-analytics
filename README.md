# Bassip 그로스해킹 대시보드

Neon(Bassip)의 데이터를 Supabase로 매일 동기화하고, GitHub Pages로 배포된 대시보드가
페이지를 열 때마다 Supabase에서 실시간으로 데이터를 불러옵니다. 실제 의뢰인 데이터가
들어있으므로 대시보드 페이지 자체에 로그인(Supabase Auth)이 걸려 있습니다.

```
Neon (bassip_ai_reader, 원본)
   │  매일 08:00 KST, GitHub Actions
   ▼
Supabase Postgres (읽기 전용 미러 + RLS)
   │  로그인한 사용자만 조회 가능
   ▼
GitHub Pages (docs/index.html) — 매 접속마다 Supabase에서 fetch
```

## 0. 준비물

- GitHub 계정, **Private** 저장소로 이 폴더를 push
- Supabase 계정 (무료 플랜으로 충분) — https://supabase.com
- Neon(bassip_ai_reader) 연결 문자열 — 이전에 psql로 접속할 때 쓰던 그 문자열

## 1. Supabase 프로젝트 생성

1. https://supabase.com/dashboard 에서 New Project 생성 (리전은 서울과 가까운 곳 추천)
2. 프로젝트가 만들어지면 **Settings → API** 에서 다음 두 값을 복사해둡니다.
   - `Project URL` (예: `https://abcdxyz.supabase.co`)
   - `anon public` key
3. **Settings → Database → Connection string** 에서 `URI` 형식의 연결 문자열을 복사해둡니다.
   (이게 `SUPABASE_DB_URL` — service_role 이 아니라 DB 자체 접속 문자열입니다. 비밀번호는
   프로젝트 생성 시 설정한 DB 비밀번호입니다.)

## 2. 스키마 + 초기 데이터 넣기

Supabase 대시보드 **SQL Editor**에서 아래 파일들을 순서대로 통째로 붙여넣고 실행하세요.

1. `supabase/schema.sql` — 테이블 3개 + RLS 정책 생성
2. `supabase/seed/seed_funnel_rows.sql`
3. `supabase/seed/seed_case_rows.sql`
4. `supabase/seed/seed_case_stage_events.sql`

(이 seed 파일들은 **현재 대시보드에 이미 들어있던 스냅샷**을 그대로 옮긴 것이라, 여기까지만
해도 대시보드는 바로 정상 작동합니다. 이후 데이터는 3번의 자동 동기화가 매일 새로 갱신합니다.)

## 3. Auth — 로그인 계정 만들기 & 회원가입 막기

실제 의뢰인 데이터라서 **아무나 로그인할 수 없게** 막아야 합니다.

1. **Authentication → Providers → Email** 에서 "Allow new users to sign up" 을 **꺼주세요.**
   (꺼두지 않으면 로그인 화면에 가입 폼이 없어도, anon key를 아는 사람이 브라우저 콘솔에서
   직접 회원가입 API를 호출해 새 계정을 만들 수 있습니다.)
2. **Authentication → Users → Add user** 로 볼 사람의 이메일/비밀번호를 직접 만들어줍니다.
   (팀원 각자 계정을 만들어도 되고, 공용 계정 하나만 만들어도 됩니다.)

## 4. 대시보드에 Supabase 값 채우기

`docs/index.html` 안에서 아래 두 줄을 찾아 1번에서 복사해둔 값으로 바꿉니다.

```js
var SUPABASE_URL = 'https://YOUR-PROJECT-REF.supabase.co';
var SUPABASE_ANON_KEY = 'YOUR-ANON-PUBLIC-KEY';
```

`anon` 키는 브라우저 소스에 그대로 노출되지만, RLS 정책이 "로그인한 사용자만 조회"로
막고 있어서 로그인하지 않은 사람은 이 키만으로는 데이터를 하나도 읽을 수 없습니다.

## 5. GitHub에 올리고 Pages 켜기

```bash
cd bassip-dashboard
git init
git add .
git commit -m "Bassip 대시보드 초기 구성"
git branch -M main
git remote add origin https://github.com/<your-account>/<repo-name>.git
git push -u origin main
```

GitHub에서 저장소를 **Private**로 만드세요 (이미 만들어져 있다면 Settings → General →
Danger Zone에서 확인). 그다음 **Settings → Pages** 에서:
- Source: `Deploy from a branch`
- Branch: `main` / `/docs`

로 설정하면 몇 분 뒤 `https://<your-account>.github.io/<repo-name>/` 에서 대시보드가 뜹니다.

> ⚠️ **중요**: Private 저장소여도 GitHub Pages로 배포하면 **그 배포 URL 자체는 링크를 아는
> 사람이면 누구나 열립니다** (GitHub Enterprise Cloud가 아닌 이상). 그래서 4번에서 만든
> 로그인 화면이 실제 접근 제한 역할을 합니다 — 반드시 3번(회원가입 차단 + 계정 직접 생성)을
> 건너뛰지 마세요.

## 6. 매일 자동 동기화 (GitHub Actions)

**Settings → Secrets and variables → Actions** 에서 시크릿 2개를 등록하세요.

- `NEON_DATABASE_URL` — bassip_ai_reader 읽기전용 연결 문자열
- `SUPABASE_DB_URL` — 1번에서 복사해둔 Supabase DB 연결 문자열

`.github/workflows/sync-data.yml` 이 매일 08:00 KST(UTC 23:00 전날)에 자동으로
`sync/sync.sh` 를 실행해서 Neon → Supabase로 최신 데이터를 다시 채워 넣습니다.
바로 한 번 테스트해보고 싶으면 저장소의 **Actions** 탭 → `Sync Bassip data` →
`Run workflow` 로 수동 실행할 수 있습니다.

### sync/neon_export.sql 검증 완료 (2026-08-28)

3개 쿼리 모두 실제 Neon 스키마와 대조 확인했고, `psql`로 직접 실행해서 정상적으로
JSON을 뽑아내는 것까지 확인했습니다(문의 3,185건/사건 1,055건/단계이력 2,645건 —
마지막 스냅샷보다 늘어난 건 그 사이 실제로 들어온 신규 데이터라 정상입니다). 그대로
쓰면 됩니다. 스키마가 나중에 바뀌면(테이블/컬럼 추가 등) 아래로 다시 확인하세요.

```bash
psql "$NEON_DATABASE_URL" -c "\d requests"
psql "$NEON_DATABASE_URL" -c "\d communications"
psql "$NEON_DATABASE_URL" -c "\d quotes"
psql "$NEON_DATABASE_URL" -c "\d contracts"
psql "$NEON_DATABASE_URL" -c "\d cases"
psql "$NEON_DATABASE_URL" -c "\d case_stage_histories"
```

## 폴더 구조

```
bassip-dashboard/
├── docs/index.html              대시보드 본체 (GitHub Pages가 이 폴더를 서빙)
├── supabase/schema.sql          테이블 + RLS 정책
├── supabase/seed/*.sql          초기 데이터 (현재 스냅샷)
├── sync/neon_export.sql         Neon에서 뽑는 3개 쿼리 (검증 완료)
├── sync/sync.sh                 Neon → Supabase 동기화 스크립트
└── .github/workflows/sync-data.yml   매일 자동 실행 워크플로
```

## 로컬에서 미리보기

`docs/index.html`은 순수 정적 파일이라 아무 방법으로나 로컬에서 열어볼 수 있습니다
(단, Supabase 값을 채워야 로그인 화면 다음 단계까지 확인됩니다). 이 컴퓨터엔 Python/Node가
따로 없으므로 PowerShell로 간단히 띄우면 됩니다.

```powershell
# 이 폴더(docs)에서 실행 — http://localhost:8080/index.html
cd docs
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:8080/")
$listener.Start()
while ($listener.IsListening) {
  $ctx = $listener.GetContext()
  $path = $ctx.Request.Url.LocalPath.TrimStart('/')
  if ([string]::IsNullOrEmpty($path)) { $path = "index.html" }
  $bytes = [System.IO.File]::ReadAllBytes((Join-Path (Get-Location) $path))
  $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
  $ctx.Response.Close()
}
```
