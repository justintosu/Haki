-- Haki — AI food features (the "food-ai" edge function).
--
-- ai_usage   per-user daily counters so one account can't run up the
--            Anthropic bill. Only the edge function (service role) touches it.
-- menu_cache restaurant menus the function has already researched, shared by
--            everyone (menus are public information). Service role only.

create table public.ai_usage (
  user_id uuid not null references auth.users (id) on delete cascade,
  day date not null,
  kind text not null check (kind in ('meal', 'menu')),
  count integer not null default 0 check (count >= 0),
  primary key (user_id, day, kind)
);

alter table public.ai_usage enable row level security;
-- No policies: clients can't read or write it. The service role bypasses RLS.

comment on table public.ai_usage is
  'Daily AI request counts per user and kind; written only by the food-ai edge function.';

create table public.menu_cache (
  place_key text primary key check (char_length(place_key) between 1 and 300),
  place_name text not null check (char_length(place_name) between 1 and 200),
  payload jsonb not null,
  created_at timestamptz not null default now()
);

alter table public.menu_cache enable row level security;
-- No policies: read and written only by the food-ai edge function.

create index menu_cache_created_at_idx on public.menu_cache (created_at);

comment on table public.menu_cache is
  'Menus researched by the food-ai edge function, reused for 14 days.';

-- Adds one request to today's count (UTC) unless the limit is reached.
-- Returns true when the request may go ahead.
create function public.consume_ai_quota(p_user uuid, p_kind text, p_limit integer)
returns boolean
language plpgsql
set search_path = ''
as $$
declare
  v_count integer;
begin
  if p_limit <= 0 then
    return false;
  end if;
  insert into public.ai_usage as u (user_id, day, kind, count)
  values (p_user, (now() at time zone 'utc')::date, p_kind, 1)
  on conflict (user_id, day, kind) do update
    set count = u.count + 1
    where u.count < p_limit
  returning u.count into v_count;
  return v_count is not null;
end;
$$;

-- Gives back a request that failed on the server's side (not the user's).
create function public.refund_ai_quota(p_user uuid, p_kind text)
returns void
language sql
set search_path = ''
as $$
  update public.ai_usage
  set count = greatest(count - 1, 0)
  where user_id = p_user
    and day = (now() at time zone 'utc')::date
    and kind = p_kind;
$$;

revoke all on function public.consume_ai_quota(uuid, text, integer) from public, anon, authenticated;
revoke all on function public.refund_ai_quota(uuid, text) from public, anon, authenticated;
grant execute on function public.consume_ai_quota(uuid, text, integer) to service_role;
grant execute on function public.refund_ai_quota(uuid, text) to service_role;

revoke all on table public.ai_usage from anon, authenticated;
revoke all on table public.menu_cache from anon, authenticated;
