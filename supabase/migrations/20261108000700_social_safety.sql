-- Social safety: server-stamped timestamps, verified portfolio posts,
-- private default usernames, onboarding-gated discovery, and reporting and
-- blocking (App Store guideline 1.2 for user-generated content).

-- 1. The server decides when things were created, so nobody can pin a post
--    above every feed by sending a future created_at.
create function private.stamp_created_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.created_at := now();
  return new;
end;
$$;
revoke execute on function private.stamp_created_at() from public, anon, authenticated;

create trigger posts_stamp_created_at before insert on public.posts
  for each row execute function private.stamp_created_at();
create trigger comments_stamp_created_at before insert on public.comments
  for each row execute function private.stamp_created_at();
create trigger post_likes_stamp_created_at before insert on public.post_likes
  for each row execute function private.stamp_created_at();
create trigger follows_stamp_created_at before insert on public.follows
  for each row execute function private.stamp_created_at();

-- 2. Portfolio posts are built from the author's real holdings (percentages
--    only), whatever the app sends, and other posts carry no attachment.
create function private.build_portfolio_attachment(p_user uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with positions as (
    select
      coalesce(h.ticker, h.name) as ticker,
      sum(h.value) as value,
      max(h.security_type) as security_type
    from public.holdings h
    where h.user_id = p_user and h.value > 0
    group by coalesce(h.ticker, h.name)
  ),
  invested as (
    select * from positions where coalesce(lower(security_type), '') <> 'cash'
  ),
  total as (
    select sum(value) as total from invested
  ),
  ranked as (
    select i.ticker, i.value, row_number() over (order by i.value desc, i.ticker) as rank
    from invested i
  ),
  items as (
    select ticker, round(100 * value / t.total, 1) as weight_pct, rank
    from ranked, total t
    where rank <= 5 and t.total > 0
    union all
    select 'Other', round(100 * sum(value) / max(t.total), 1), 6
    from ranked, total t
    where rank > 5 and t.total > 0
    having sum(value) > 0
  ),
  gain as (
    select round(100 * (sum(h.value) - sum(h.cost_basis)) / nullif(sum(h.cost_basis), 0), 1) as pct
    from public.holdings h
    where h.user_id = p_user and h.value > 0 and h.cost_basis > 0
  )
  select case
    when not exists (select 1 from items) then null
    else jsonb_build_object(
      'holdings', (select jsonb_agg(jsonb_build_object('ticker', ticker, 'weight_pct', weight_pct) order by rank) from items),
      'total_gain_pct', (select pct from gain)
    )
  end;
$$;
revoke execute on function private.build_portfolio_attachment(uuid) from public, anon, authenticated;

create function private.verify_post_attachment()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.kind = 'portfolio' then
    new.attachment := private.build_portfolio_attachment(new.author_id);
    if new.attachment is null then
      raise exception 'Connect a brokerage before sharing your portfolio.'
        using errcode = 'P0001';
    end if;
  else
    new.attachment := null;
  end if;
  return new;
end;
$$;
revoke execute on function private.verify_post_attachment() from public, anon, authenticated;

create trigger posts_verify_attachment before insert on public.posts
  for each row execute function private.verify_post_attachment();

-- 3. A regular post's ticker follows its caption when the caption is edited.
create function private.sync_post_ticker()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  tag text;
begin
  if new.kind = 'post' then
    tag := upper(substring(new.caption from '(?:^|[^A-Za-z0-9$])\$([A-Za-z][A-Za-z0-9.\-]{0,9})'));
    tag := rtrim(tag, '.');
    if tag is not null and tag !~ '^[A-Z][A-Z0-9.\-]{0,9}$' then
      tag := null;
    end if;
    new.ticker := tag;
  end if;
  return new;
end;
$$;
revoke execute on function private.sync_post_ticker() from public, anon, authenticated;

create trigger posts_sync_ticker before update of caption on public.posts
  for each row execute function private.sync_post_ticker();

-- 4. New accounts get a random username instead of one derived from their
--    email address (usernames are visible to every signed-in user). People
--    pick their own during onboarding.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  candidate text;
begin
  loop
    candidate := 'user' || substr(md5(random()::text || clock_timestamp()::text || new.id::text), 1, 8);
    exit when not exists (select 1 from public.profiles where username = candidate);
  end loop;

  insert into public.profiles (id, username, display_name)
  values (
    new.id,
    candidate,
    left(coalesce(new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'name', ''), 50)
  );
  return new;
end;
$$;

-- 5. Reporting.
create table public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  reported_user_id uuid references public.profiles (id) on delete set null,
  post_id uuid references public.posts (id) on delete set null,
  comment_id uuid references public.comments (id) on delete set null,
  reason text not null check (reason in ('spam', 'harassment', 'hate', 'scam', 'sexual', 'violence', 'other')),
  created_at timestamptz not null default now()
);

create index reports_reporter_id_idx on public.reports (reporter_id);
create index reports_reported_user_id_idx on public.reports (reported_user_id);
create index reports_post_id_idx on public.reports (post_id);
create index reports_comment_id_idx on public.reports (comment_id);

alter table public.reports enable row level security;
create policy "Users report as themselves"
  on public.reports for insert to authenticated
  with check ((select auth.uid()) = reporter_id);
revoke select, update, delete on public.reports from anon, authenticated;

create trigger reports_stamp_created_at before insert on public.reports
  for each row execute function private.stamp_created_at();

-- 6. Blocking.
create table public.blocks (
  blocker_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  blocked_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);

create index blocks_blocked_id_idx on public.blocks (blocked_id);

alter table public.blocks enable row level security;
create policy "Users see their blocks"
  on public.blocks for select to authenticated
  using ((select auth.uid()) = blocker_id);
create policy "Users block as themselves"
  on public.blocks for insert to authenticated
  with check ((select auth.uid()) = blocker_id);
create policy "Users unblock as themselves"
  on public.blocks for delete to authenticated
  using ((select auth.uid()) = blocker_id);
revoke update on public.blocks from anon, authenticated;

create trigger blocks_stamp_created_at before insert on public.blocks
  for each row execute function private.stamp_created_at();

-- Whether either user has blocked the other.
create function private.blocked_between(a uuid, b uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select a is not null and b is not null and exists (
    select 1 from public.blocks
    where (blocker_id = a and blocked_id = b) or (blocker_id = b and blocked_id = a)
  );
$$;
revoke execute on function private.blocked_between(uuid, uuid) from public, anon;
grant execute on function private.blocked_between(uuid, uuid) to authenticated;

-- Blocking ends follows in both directions.
create function private.end_follows_on_block()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.follows
  where (follower_id = new.blocker_id and followee_id = new.blocked_id)
     or (follower_id = new.blocked_id and followee_id = new.blocker_id);
  return new;
end;
$$;
revoke execute on function private.end_follows_on_block() from public, anon, authenticated;

create trigger blocks_end_follows after insert on public.blocks
  for each row execute function private.end_follows_on_block();

-- A blocked person can't follow you or comment on your posts.
alter policy "Users follow as themselves"
  on public.follows
  with check (
    (select auth.uid()) = follower_id
    and not private.blocked_between((select auth.uid()), followee_id)
  );

alter policy "Users comment as themselves"
  on public.comments
  with check (
    (select auth.uid()) = author_id
    and not private.blocked_between(
      (select auth.uid()),
      (select p.author_id from public.posts p where p.id = post_id)
    )
  );

-- Blocked people disappear from feeds, comments, activity and discovery.
create or replace view public.feed_posts
with (security_invoker = true)
as
select
  p.id,
  p.author_id,
  p.kind,
  p.caption,
  p.image_path,
  p.ticker,
  p.trade_side,
  p.attachment,
  p.like_count,
  p.comment_count,
  p.created_at,
  pr.username as author_username,
  pr.display_name as author_display_name,
  pr.avatar_path as author_avatar_path,
  exists (
    select 1 from public.post_likes l
    where l.post_id = p.id and l.user_id = (select auth.uid())
  ) as liked_by_me,
  (p.ticker is not null and private.holds_ticker(p.author_id, p.ticker)) as author_holds_ticker
from public.posts p
join public.profiles pr on pr.id = p.author_id
where not private.blocked_between((select auth.uid()), p.author_id);

create or replace view public.comment_details
with (security_invoker = true)
as
select
  c.id,
  c.post_id,
  c.author_id,
  c.body,
  c.created_at,
  pr.username as author_username,
  pr.display_name as author_display_name,
  pr.avatar_path as author_avatar_path
from public.comments c
join public.profiles pr on pr.id = c.author_id
where not private.blocked_between((select auth.uid()), c.author_id);

create or replace function public.search_profiles(p_query text, p_limit integer default 20)
returns setof public.profile_stats
language sql
stable
security invoker
set search_path = ''
as $$
  with q as (
    select replace(replace(replace(lower(trim(p_query)), '\', '\\'), '%', '\%'), '_', '\_') as pattern,
           lower(trim(p_query)) as raw
  )
  select s.*
  from public.profile_stats s
  join public.profiles p on p.id = s.id and p.onboarded
  cross join q
  where q.raw <> ''
    and (s.username ilike '%' || q.pattern || '%' or s.display_name ilike '%' || q.pattern || '%')
    and not private.blocked_between((select auth.uid()), s.id)
  order by (s.username = q.raw) desc, s.follower_count desc, s.username
  limit least(greatest(p_limit, 1), 50);
$$;

create or replace function public.suggested_profiles(p_limit integer default 20)
returns setof public.profile_stats
language sql
stable
security invoker
set search_path = ''
as $$
  select s.*
  from public.profile_stats s
  join public.profiles p on p.id = s.id and p.onboarded
  where s.id <> (select auth.uid())
    and not s.followed_by_me
    and not private.blocked_between((select auth.uid()), s.id)
  order by s.follower_count desc, s.post_count desc, s.created_at desc
  limit least(greatest(p_limit, 1), 50);
$$;

create or replace function public.get_activity(p_limit integer default 50)
returns table (
  kind text,
  actor_id uuid,
  actor_username text,
  actor_display_name text,
  actor_avatar_path text,
  post_id uuid,
  post_image_path text,
  comment_body text,
  created_at timestamptz
)
language sql
stable
security invoker
set search_path = ''
as $$
  select * from (
    select 'like'::text, l.user_id, pr.username, pr.display_name, pr.avatar_path, p.id, p.image_path, null::text, l.created_at
    from public.post_likes l
    join public.posts p on p.id = l.post_id
    join public.profiles pr on pr.id = l.user_id
    where p.author_id = (select auth.uid()) and l.user_id <> (select auth.uid())
    union all
    select 'comment', c.author_id, pr.username, pr.display_name, pr.avatar_path, p.id, p.image_path, c.body, c.created_at
    from public.comments c
    join public.posts p on p.id = c.post_id
    join public.profiles pr on pr.id = c.author_id
    where p.author_id = (select auth.uid()) and c.author_id <> (select auth.uid())
    union all
    select 'follow', f.follower_id, pr.username, pr.display_name, pr.avatar_path, null::uuid, null::text, null::text, f.created_at
    from public.follows f
    join public.profiles pr on pr.id = f.follower_id
    where f.followee_id = (select auth.uid())
  ) activity (kind, actor_id, actor_username, actor_display_name, actor_avatar_path, post_id, post_image_path, comment_body, created_at)
  where not private.blocked_between((select auth.uid()), activity.actor_id)
  order by created_at desc
  limit least(greatest(p_limit, 1), 100);
$$;

