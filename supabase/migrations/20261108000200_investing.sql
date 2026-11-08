-- Brokerage connections through Plaid. Edge functions (service role) write
-- every table here; clients can only read their own rows, and can never read
-- Plaid access tokens.

create table public.plaid_items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  item_id text not null unique,
  access_token text not null,
  created_at timestamptz not null default now()
);

create index plaid_items_user_id_idx on public.plaid_items (user_id);
alter table public.plaid_items enable row level security;
-- No policies on purpose: only the service role can use this table.
revoke all on public.plaid_items from anon, authenticated;

create table public.brokerage_connections (
  id uuid primary key default gen_random_uuid(),
  plaid_item_id uuid not null unique references public.plaid_items (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  institution_id text,
  institution_name text not null default 'Brokerage',
  status text not null default 'active' check (status in ('active', 'needs_attention', 'error')),
  error_message text,
  last_synced_at timestamptz,
  created_at timestamptz not null default now()
);

create index brokerage_connections_user_id_idx on public.brokerage_connections (user_id);

create table public.investment_accounts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  connection_id uuid not null references public.brokerage_connections (id) on delete cascade,
  plaid_account_id text not null unique,
  name text not null default '',
  official_name text,
  mask text,
  type text not null default '',
  subtype text,
  current_balance numeric(20, 4),
  currency text not null default 'USD',
  updated_at timestamptz not null default now()
);

create index investment_accounts_user_id_idx on public.investment_accounts (user_id);
create index investment_accounts_connection_id_idx on public.investment_accounts (connection_id);

create table public.holdings (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  account_id uuid not null references public.investment_accounts (id) on delete cascade,
  security_id text not null,
  ticker text,
  name text not null default '',
  -- Plaid security type: equity, etf, mutual fund, cash, cryptocurrency, derivative, fixed income, other.
  security_type text,
  quantity numeric(24, 8) not null default 0,
  price numeric(20, 6),
  price_as_of date,
  value numeric(20, 4) not null default 0,
  cost_basis numeric(20, 4),
  currency text not null default 'USD',
  updated_at timestamptz not null default now(),
  unique (account_id, security_id)
);

create index holdings_user_id_idx on public.holdings (user_id);
create index holdings_user_ticker_idx on public.holdings (user_id, ticker);

create table public.investment_transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  account_id uuid not null references public.investment_accounts (id) on delete cascade,
  plaid_transaction_id text not null unique,
  date date not null,
  name text not null default '',
  ticker text,
  security_name text,
  -- Plaid type: buy, sell, cancel, cash, fee, transfer.
  type text not null default '',
  subtype text,
  quantity numeric(24, 8),
  price numeric(20, 6),
  amount numeric(20, 4),
  fees numeric(20, 4),
  currency text not null default 'USD'
);

create index investment_transactions_user_date_idx on public.investment_transactions (user_id, date desc);
create index investment_transactions_account_id_idx on public.investment_transactions (account_id);

create table public.portfolio_snapshots (
  user_id uuid not null references auth.users (id) on delete cascade,
  date date not null,
  total_value numeric(20, 4) not null,
  cost_basis numeric(20, 4),
  primary key (user_id, date)
);

-- Owners can read their own rows; nobody writes from the client.
alter table public.brokerage_connections enable row level security;
alter table public.investment_accounts enable row level security;
alter table public.holdings enable row level security;
alter table public.investment_transactions enable row level security;
alter table public.portfolio_snapshots enable row level security;

create policy "Owners read their brokerage connections"
  on public.brokerage_connections for select to authenticated
  using ((select auth.uid()) = user_id);
create policy "Owners read their investment accounts"
  on public.investment_accounts for select to authenticated
  using ((select auth.uid()) = user_id);
create policy "Owners read their holdings"
  on public.holdings for select to authenticated
  using ((select auth.uid()) = user_id);
create policy "Owners read their investment transactions"
  on public.investment_transactions for select to authenticated
  using ((select auth.uid()) = user_id);
create policy "Owners read their portfolio snapshots"
  on public.portfolio_snapshots for select to authenticated
  using ((select auth.uid()) = user_id);

revoke insert, update, delete on
  public.brokerage_connections,
  public.investment_accounts,
  public.holdings,
  public.investment_transactions,
  public.portfolio_snapshots
from anon, authenticated;
revoke all on
  public.brokerage_connections,
  public.investment_accounts,
  public.holdings,
  public.investment_transactions,
  public.portfolio_snapshots
from anon;

-- A user's holdings as percentages, for profiles. Returns nothing unless the
-- user shares their portfolio (or it's the caller's own).
create function public.public_portfolio(p_user uuid)
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
      sum(h.cost_basis) as cost_basis
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
    case when p.cost_basis > 0 then round(100 * (p.value - p.cost_basis) / p.cost_basis, 2) end as gain_pct
  from positions p
  cross join total t
  order by p.value desc;
$$;

-- Whole-portfolio return as a percentage, same visibility rules.
create function public.public_portfolio_summary(p_user uuid)
returns table (position_count integer, total_gain_pct numeric, updated_at timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  select
    count(distinct coalesce(h.ticker, h.name))::integer as position_count,
    case
      when sum(h.cost_basis) filter (where h.cost_basis > 0) > 0 then
        round(100 * (sum(h.value) filter (where h.cost_basis > 0) - sum(h.cost_basis) filter (where h.cost_basis > 0))
              / sum(h.cost_basis) filter (where h.cost_basis > 0), 2)
    end as total_gain_pct,
    max(h.updated_at) as updated_at
  from public.holdings h
  join public.profiles pr on pr.id = h.user_id
  where h.user_id = p_user
    and h.value > 0
    and (pr.share_portfolio or pr.id = (select auth.uid()));
$$;

-- Whether a user holds a ticker, for the "holds" badge on posts. Same visibility rules.
create function public.holds_ticker(p_user uuid, p_ticker text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.holdings h
    join public.profiles pr on pr.id = h.user_id
    where h.user_id = p_user
      and h.ticker = p_ticker
      and h.quantity > 0
      and (pr.share_portfolio or pr.id = (select auth.uid()))
  );
$$;

revoke execute on function public.public_portfolio(uuid) from public, anon;
revoke execute on function public.public_portfolio_summary(uuid) from public, anon;
revoke execute on function public.holds_ticker(uuid, text) from public, anon;
grant execute on function public.public_portfolio(uuid) to authenticated;
grant execute on function public.public_portfolio_summary(uuid) to authenticated;
grant execute on function public.holds_ticker(uuid, text) to authenticated;
