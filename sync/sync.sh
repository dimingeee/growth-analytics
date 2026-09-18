#!/usr/bin/env bash
# Neon(Bassip) -> Supabase 데이터 동기화. GitHub Actions에서 매일 실행됩니다.
# 로컬에서 수동으로 돌리려면: NEON_DATABASE_URL=... SUPABASE_DB_URL=... bash sync/sync.sh
set -euo pipefail

: "${NEON_DATABASE_URL:?NEON_DATABASE_URL 환경변수를 설정하세요 (bassip_ai_reader 읽기전용 연결 문자열)}"
: "${SUPABASE_DB_URL:?SUPABASE_DB_URL 환경변수를 설정하세요 (Supabase Settings > Database > Connection string, service_role 아님 — DB 접속 문자열)}"

QFILE="$(cd "$(dirname "$0")" && pwd)/neon_export.sql"

# 기존 Supabase 프로젝트를 별도 수동 마이그레이션 없이 확장한다.
psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 <<'SQL'
alter table funnel_rows add column if not exists source_platform text;
alter table funnel_rows add column if not exists stage_updated_at timestamptz;
alter table funnel_rows add column if not exists company_id text;
alter table funnel_rows add column if not exists source_medium text;
alter table funnel_rows add column if not exists source_creative text;
alter table case_rows add column if not exists contract_amount numeric;
alter table case_rows add column if not exists comm_count integer;
create table if not exists request_stage_events (
  id bigserial primary key,
  request_id text not null,
  from_stage text,
  to_stage text not null,
  changed_at timestamptz not null
);
create index if not exists idx_request_stage_events_request_id on request_stage_events (request_id);
alter table request_stage_events enable row level security;
drop policy if exists "authenticated read request_stage_events" on request_stage_events;
create policy "authenticated read request_stage_events" on request_stage_events
  for select using (auth.role() = 'authenticated');
SQL

# neon_export.sql에서 "-- @query: <name>" 블록 하나를 뽑아 순수 SQL만 반환
extract_query() {
  local name="$1"
  awk -v marker="-- @query: $name" '
    $0 == marker { flag=1; next }
    /^-- @query:/ { flag=0 }
    flag { print }
  ' "$QFILE"
}

# $1=query 이름  $2=Supabase 테이블명  $3=INSERT용 컬럼 목록  $4=json_to_recordset AS 정의
sync_table() {
  local qname="$1" table="$2" cols="$3" recdef="$4"
  echo "== [$table] Neon에서 조회 중 (query: $qname) =="
  local json
  json="$(psql "$NEON_DATABASE_URL" -t -A -c "$(extract_query "$qname")")"
  if [ -z "$json" ] || [ "$json" = "[]" ]; then
    echo "!! [$table] 조회 결과가 비어 있습니다. neon_export.sql의 쿼리를 확인하세요. 동기화를 건너뜁니다." >&2
    return 1
  fi
  echo "== [$table] Supabase로 적재 중 =="
  psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 <<SQL
begin;
truncate table $table;
insert into $table ($cols)
select $cols
from json_to_recordset(\$sync_json\$${json}\$sync_json\$::json) as x($recdef);
commit;
SQL
  echo "== [$table] 완료 =="
}

sync_table "funnel_rows" "funnel_rows" \
  "id, inquiry_at, category, channel, phase, stage, stage_updated_at, first_contact_at, first_quote_at, first_contract_at, unqualified_reason, source_platform, company_id, source_medium, source_creative" \
  "id text, inquiry_at timestamptz, category text, channel text, phase text, stage text, stage_updated_at timestamptz, first_contact_at timestamptz, first_quote_at timestamptz, first_contract_at timestamptz, unqualified_reason text, source_platform text, company_id text, source_medium text, source_creative text"

sync_table "case_rows" "case_rows" \
  "id, request_id, inquiry_at, first_contact_at, first_quote_at, contract_date, commission_date, filing_official_date, registration_official_date, ip_type, category, assignee_id, contract_amount, comm_count" \
  "id text, request_id text, inquiry_at timestamptz, first_contact_at timestamptz, first_quote_at timestamptz, contract_date timestamptz, commission_date timestamptz, filing_official_date timestamptz, registration_official_date timestamptz, ip_type text, category text, assignee_id text, contract_amount numeric, comm_count integer"

sync_table "case_stage_events" "case_stage_events" \
  "case_id, stage, changed_at" \
  "case_id text, stage text, changed_at timestamptz"

sync_table "request_stage_events" "request_stage_events" \
  "request_id, from_stage, to_stage, changed_at" \
  "request_id text, from_stage text, to_stage text, changed_at timestamptz"

psql "$SUPABASE_DB_URL" -t -A -c "select '유입 플랫폼(utm_source) 집계: 전체값=' || count(source_platform) || ', 소재(utm_term/content) 있음=' || count(source_creative) from funnel_rows;"

echo "모든 테이블 동기화 완료."
