-- Bassip 그로스해킹 대시보드 — Supabase 스키마
-- Supabase 대시보드 > SQL Editor 에 이 파일 전체를 붙여넣고 실행하세요.

-- =========================================================
-- 1. 테이블
-- =========================================================

-- 문의(요청) 단위 초기 퍼널 데이터 (문의접수 → 첫연락 → 첫견적 → 첫계약)
create table if not exists funnel_rows (
  id text primary key,
  inquiry_at timestamptz,
  category text,
  channel text,
  phase text,
  stage text,
  first_contact_at timestamptz,
  first_quote_at timestamptz,
  first_contract_at timestamptz,
  unqualified_reason text
);

-- 사건 단위 데이터 (계약 체결 이후 진행 상황)
create table if not exists case_rows (
  id text primary key,
  request_id text,
  inquiry_at timestamptz,
  first_contact_at timestamptz,
  first_quote_at timestamptz,
  contract_date timestamptz,
  commission_date timestamptz,
  filing_official_date timestamptz,
  registration_official_date timestamptz,
  ip_type text,
  category text,
  assignee_id text
);

-- 사건 진행 단계 이력 (사건 1건당 여러 row)
create table if not exists case_stage_events (
  id bigserial primary key,
  case_id text not null,
  stage text not null,
  changed_at timestamptz not null
);
create index if not exists idx_case_stage_events_case_id on case_stage_events (case_id);

-- =========================================================
-- 2. Row Level Security — 로그인한 사용자만 조회 가능, 쓰기는 아무도 못 함
--    (데이터 갱신은 GitHub Actions가 service_role 키로 하며, service_role은 RLS를 무시함)
-- =========================================================

alter table funnel_rows enable row level security;
alter table case_rows enable row level security;
alter table case_stage_events enable row level security;

drop policy if exists "authenticated read funnel_rows" on funnel_rows;
create policy "authenticated read funnel_rows" on funnel_rows
  for select using (auth.role() = 'authenticated');

drop policy if exists "authenticated read case_rows" on case_rows;
create policy "authenticated read case_rows" on case_rows
  for select using (auth.role() = 'authenticated');

drop policy if exists "authenticated read case_stage_events" on case_stage_events;
create policy "authenticated read case_stage_events" on case_stage_events
  for select using (auth.role() = 'authenticated');

-- insert/update/delete 정책을 아예 만들지 않았으므로, anon/authenticated 키로는
-- 어떤 경로로도 이 테이블을 쓸 수 없습니다 (읽기 전용).
