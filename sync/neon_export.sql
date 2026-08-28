-- Neon(Bassip) 추출 쿼리 — 2026-08-28 실제 스키마 대조 검증 완료 (psql로 \d 조회 + 행수 대조 확인함).
-- sync/sync.sh 가 이 파일을 "-- @query: <name>" 마커로 구분해서 하나씩 실행합니다.
-- 각 쿼리는 json_agg(row_to_json(t))로 JSON 배열 한 줄을 출력합니다.

-- @query: funnel_rows
select coalesce(json_agg(row_to_json(t)), '[]'::json) from (
  with first_contact as (
    select request_id, min(occurred_at) as at
    from public.communications
    where direction = 'outbound' and request_id is not null
    group by request_id
  ),
  first_quote as (
    select request_id, min(quote_date) as at
    from public.quotes
    where deleted_at is null
    group by request_id
  ),
  req_contracts as (
    select request_id, min(contract_date) as first_contract_at
    from public.contracts
    where deleted_at is null and request_id is not null
    group by request_id
  )
  select
    r.id,
    r.inquiry_date as inquiry_at,
    r.category,
    r.inbound_channel::text as channel,
    r.phase::text as phase,
    r.stage::text as stage,
    fc.at as first_contact_at,
    fq.at as first_quote_at,
    rc.first_contract_at,
    r.unqualified_reason
  from public.requests r
  left join first_contact fc on fc.request_id = r.id
  left join first_quote fq on fq.request_id = r.id
  left join req_contracts rc on rc.request_id = r.id
  where r.deleted_at is null and r.inquiry_date is not null
  order by r.inquiry_date
) t;

-- @query: case_rows
select coalesce(json_agg(row_to_json(t)), '[]'::json) from (
  with first_contact as (
    select request_id, min(occurred_at) as at
    from public.communications
    where direction = 'outbound' and request_id is not null
    group by request_id
  ),
  first_quote as (
    select request_id, min(quote_date) as at
    from public.quotes
    where deleted_at is null
    group by request_id
  )
  select
    cs.id,
    coalesce(r.id, '') as request_id,
    r.inquiry_date as inquiry_at,
    fc.at as first_contact_at,
    fq.at as first_quote_at,
    c.contract_date,
    cs.commission_date,
    cs.filing_date as filing_official_date,
    cs.registration_date as registration_official_date,
    cs.ip_type::text as ip_type,
    r.category,
    cs.assignee_id
  from public.cases cs
  left join public.contracts c on c.id = cs.contract_id and c.deleted_at is null
  left join public.requests r on r.id = c.request_id and r.deleted_at is null
  left join first_contact fc on fc.request_id = r.id
  left join first_quote fq on fq.request_id = r.id
  where cs.deleted_at is null
  order by cs.commission_date
) t;

-- @query: case_stage_events
select coalesce(json_agg(row_to_json(t)), '[]'::json) from (
  select
    case_id,
    to_stage as stage,
    min(changed_at) as changed_at
  from public.case_stage_histories
  where to_stage is not null and deleted_at is null
  group by case_id, to_stage
) t;
