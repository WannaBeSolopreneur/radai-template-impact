-- Snowflake row access policy for this model.
-- Not executed by the DuckDB demo. The live demo enforces the same predicate
-- in every mart, with var customer_id, and drops test fixtures there too.
--
-- Internal analysts are in RAD_INTERNAL_ANALYTICS and can read every customer.
-- A customer role is listed in governance.role_customer_access for exactly one
-- customer_id. The key is customer_id because that is the account on the fact.

create schema if not exists governance;

create or replace table governance.role_customer_access (
    role_name varchar,
    customer_id varchar
);

-- Example grants. Load these from the application, do not hard-code customers.
-- insert into governance.role_customer_access values
--     ('NORTHBAY_ANALYST', 'cust_northbay'),
--     ('REDCEDAR_ANALYST', 'cust_redcedar');

create or replace row access policy governance.rad_customer_isolation
as (customer_id varchar) returns boolean ->
    is_role_in_session('RAD_INTERNAL_ANALYTICS')
    or exists (
        select 1
        from governance.role_customer_access as access
        where access.role_name = current_role()
          and access.customer_id = customer_id
    );

-- Apply the policy to every customer-facing table that carries customer_id.
-- alter table marts.fct_studies
--   add row access policy governance.rad_customer_isolation on (customer_id);
-- alter table marts.fct_studies_metric
--   add row access policy governance.rad_customer_isolation on (customer_id);
-- alter table marts.mart_headline
--   add row access policy governance.rad_customer_isolation on (customer_id);
-- alter table marts.mart_case_mix_change
--   add row access policy governance.rad_customer_isolation on (customer_id);
-- alter table marts.mart_weekly_turnaround
--   add row access policy governance.rad_customer_isolation on (customer_id);
-- alter table marts.mart_site_turnaround
--   add row access policy governance.rad_customer_isolation on (customer_id);
-- alter table marts.mart_heatmap
--   add row access policy governance.rad_customer_isolation on (customer_id);
-- alter table marts.mart_modality_box
--   add row access policy governance.rad_customer_isolation on (customer_id);
-- alter table marts.mart_ai_specialty
--   add row access policy governance.rad_customer_isolation on (customer_id);

-- The page and the semantic layer also state the predicate in SQL, so a
-- person can see why a row is in or out. The policy is the backstop.
-- Do not give a customer role a bypass.
