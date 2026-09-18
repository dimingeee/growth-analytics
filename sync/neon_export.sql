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
    r.updated_at as stage_updated_at,
    fc.at as first_contact_at,
    fq.at as first_quote_at,
    rc.first_contract_at,
    r.unqualified_reason,
    r.company_id,
    nullif(r.utm_source, '') as source_platform,
    nullif(r.utm_medium, '') as source_medium,
    coalesce(nullif(r.utm_term, ''), nullif(r.utm_content, '')) as source_creative
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
    cs.assignee_id,
    c.supply_amount as contract_amount,
    (select count(*) from public.communications cm where cm.request_id = r.id) as comm_count
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

-- @query: request_stage_events
-- 리드에는 case_stage_histories 같은 전용 이력 테이블이 없다. 대신 담당자가 단계를 바꿀 때마다
-- communications.body에 "의뢰 단계 new → qualified" 형태의 한 줄짜리 메모를 남기고 있어(2026-09-18
-- psql로 실측: (?n) 멀티라인 매치 기준 3,504건 / 리드 2,139건 커버) 이를 파싱해서 이력을 복원한다.
select coalesce(json_agg(row_to_json(t)), '[]'::json) from (
  select
    c.request_id,
    substring(c.body from '(?n)^의뢰 단계 (\S+) →') as from_stage,
    substring(c.body from '(?n)→ (\S+)$') as to_stage,
    c.occurred_at as changed_at
  from public.communications c
  where c.body ~ '(?n)^의뢰 단계 \S+ → \S+$'
    and c.request_id is not null
    and c.deleted_at is null
  order by c.request_id, c.occurred_at
) t;
