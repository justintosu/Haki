-- A position's return only counts the lots that report what was paid, so a
-- position where some lots lack a cost basis isn't shown with an inflated
-- gain. Weights still use the full value. Same rule as
-- public_portfolio_summary and the app's PortfolioMath.

create or replace function public.public_portfolio(p_user uuid)
returns table (ticker text, name text, security_type text, weight_pct numeric, gain_pct numeric)
language sql
stable
security definer
set search_path = ''
as $$
  with visible as (
    select 1
    from public.profiles pr
    where pr.id = p_user and (pr.share_portfolio or pr.id = (select auth.uid()))
  ),
  positions as (
    select
      coalesce(h.ticker, h.name) as ticker,
      max(h.name) as name,
      max(h.security_type) as security_type,
      sum(h.value) as value,
      sum(h.value) filter (where h.cost_basis > 0) as value_with_cost,
      sum(h.cost_basis) filter (where h.cost_basis > 0) as cost_basis
    from public.holdings h
    where h.user_id = p_user and h.value > 0 and exists (select 1 from visible)
    group by coalesce(h.ticker, h.name)
  ),
  total as (
    select sum(value) as total from positions
  )
  select
    p.ticker,
    p.name,
    p.security_type,
    round(100 * p.value / nullif(t.total, 0), 2) as weight_pct,
    case when p.cost_basis > 0 then round(100 * (p.value_with_cost - p.cost_basis) / p.cost_basis, 2) end as gain_pct
  from positions p
  cross join total t
  order by p.value desc;
$$;
