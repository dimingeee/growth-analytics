-- ⚠️ 검증 필요 (IMPORTANT — VERIFY BEFORE RELYING ON THIS):
-- 이 3개 쿼리는 기존 대시보드를 만들 때 썼던 조인 로직을 기억을 바탕으로 재현한 것입니다.
-- Bassip Neon DB(bassip_ai_reader 롤)의 실제 컬럼명과 100% 대조 확인된 것이 아니므로,
-- 아래 psql 명령으로 실제 스키마를 먼저 확인하고 필요하면 컬럼명을 고치세요:
--
--   psql "$NEON_DATABASE_URL" -c "\d requests"
--   psql "$NEON_DATABASE_URL" -c "\d communications"
--   psql "$NEON_DATABASE_URL" -c "\d quotes"
--   psql "$NEON_DATABASE_URL" -c "\d contracts"
--   psql "$NEON_DATABASE_URL" -c "\d cases"
--   psql "$NEON_DATABASE_URL" -c "\d case_stage_histories"
--
-- 각 쿼리는 psql -t -A -c 로 실행되어 JSON 한 줄(문자열)로 출력됩니다.
-- sync/sync.sh 가 이 파일을 3개 쿼리로 나눠서 각각 실행합니다 (-- @query: 주석으로 구분).

-- @query: funnel_rows
select coalesce(json_agg(row_to_json(t)), '[]'::json) from (
  select
    r.id::text as id,
    r.inquiry_at,
    r.category,
    r.channel,
    r.phase,
    r.stage,
    fc.first_contact_at,
    fq.first_quote_at,
    fco.first_contract_at,
    r.unqualified_reason
  from requests r
  left join lateral (
    select min(c.sent_at) as first_contact_at
    from communications c
    where c.request_id = r.id and c.direction = 'outbound'
  ) fc on true
  left join lateral (
    select min(q.created_at) as first_quote_at
    from quotes q
    where q.request_id = r.id
  ) fq on true
  left join lateral (
    select min(ct.contract_date) as first_contract_at
    from contracts ct
    where ct.request_id = r.id
  ) fco on true
  order by r.inquiry_at
) t;

-- @query: case_rows
select coalesce(json_agg(row_to_json(t)), '[]'::json) from (
  select
    c.id::text as id,
    c.request_id::text as request_id,
    r.inquiry_at,
    fc.first_contact_at,
    fq.first_quote_at,
    ct.contract_date,
    c.commission_date,
    c.filing_date as filing_official_date,
    c.registration_date as registration_official_date,
    c.ip_type,
    c.category,
    c.assignee_id
  from cases c
  left join contracts ct on ct.id = c.contract_id
  left join requests r on r.id = ct.request_id
  left join lateral (
    select min(cm.sent_at) as first_contact_at
    from communications cm
    where cm.request_id = r.id and cm.direction = 'outbound'
  ) fc on true
  left join lateral (
    select min(q.created_at) as first_quote_at
    from quotes q
    where q.request_id = r.id
  ) fq on true
  order by c.commission_date
) t;

-- @query: case_stage_events
select coalesce(json_agg(row_to_json(t)), '[]'::json) from (
  select
    h.case_id::text as case_id,
    h.to_stage as stage,
    min(h.changed_at) as changed_at
  from case_stage_histories h
  group by h.case_id, h.to_stage
  order by h.case_id
) t;
