-- The clock repair is proven on qa_chrono. A population-wide backward clock
-- cannot be shifted forward again without eating the queue, so this only
-- requires that the fixture repair fired.
select 'repairs'
where (
    select sum(chronology_was_repaired)
    from {{ ref('stg_studies') }}
) < 1

union all

select 'fills'
where (
    select sum(modality_was_filled)
    from {{ ref('stg_studies') }}
) < 30

union all

select 'dupes'
where (
    select sum(case when raw_copy_count > 1 then 1 else 0 end)
    from {{ ref('stg_studies') }}
) < 50
