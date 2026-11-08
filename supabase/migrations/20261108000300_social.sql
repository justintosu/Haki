-- Social graph, posts, likes and comments.

create table public.follows (
  follower_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  followee_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (follower_id, followee_id),
  check (follower_id <> followee_id)
);

create index follows_followee_id_idx on public.follows (followee_id);

alter table public.follows enable row level security;

create policy "Signed-in users can see follows"
  on public.follows for select to authenticated
  using (true);
create policy "Users follow as themselves"
  on public.follows for insert to authenticated
  with check ((select auth.uid()) = follower_id);
create policy "Users unfollow as themselves"
  on public.follows for delete to authenticated
  using ((select auth.uid()) = follower_id);

revoke update on public.follows from anon, authenticated;

create table public.posts (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  -- post: a regular post; trade: shares a buy/sell of `ticker`; portfolio: shares an allocation snapshot.
  kind text not null default 'post' check (kind in ('post', 'trade', 'portfolio')),
  caption text not null default '' check (char_length(caption) <= 2200),
  -- Path inside the public "post-images" bucket, e.g. "<user id>/<uuid>.jpg".
  image_path text,
  ticker text check (ticker ~ '^[A-Z][A-Z0-9.\-]{0,9}$'),
  trade_side text check (trade_side in ('buy', 'sell')),
  -- For portfolio posts: {"holdings": [{"ticker": "AAPL", "weight_pct": 12.5}], "total_gain_pct": 8.1}.
  -- Percentages only, never amounts.
  attachment jsonb,
  like_count integer not null default 0 check (like_count >= 0),
  comment_count integer not null default 0 check (comment_count >= 0),
  created_at timestamptz not null default now(),
  check (char_length(caption) > 0 or image_path is not null or attachment is not null),
  check (kind <> 'trade' or (ticker is not null and trade_side is not null))
);

create index posts_created_at_idx on public.posts (created_at desc);
create index posts_author_created_at_idx on public.posts (author_id, created_at desc);
create index posts_ticker_created_at_idx on public.posts (ticker, created_at desc) where ticker is not null;

alter table public.posts enable row level security;

create policy "Signed-in users can see posts"
  on public.posts for select to authenticated
  using (true);
create policy "Users post as themselves"
  on public.posts for insert to authenticated
  with check ((select auth.uid()) = author_id and like_count = 0 and comment_count = 0);
create policy "Authors can edit their posts"
  on public.posts for update to authenticated
  using ((select auth.uid()) = author_id)
  with check ((select auth.uid()) = author_id);
create policy "Authors can delete their posts"
  on public.posts for delete to authenticated
  using ((select auth.uid()) = author_id);

-- Only the caption is editable; counts are maintained by triggers.
revoke update on public.posts from anon, authenticated;
grant update (caption) on public.posts to authenticated;

create table public.post_likes (
  post_id uuid not null references public.posts (id) on delete cascade,
  user_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);

create index post_likes_user_id_idx on public.post_likes (user_id);

alter table public.post_likes enable row level security;

create policy "Signed-in users can see likes"
  on public.post_likes for select to authenticated
  using (true);
create policy "Users like as themselves"
  on public.post_likes for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy "Users unlike as themselves"
  on public.post_likes for delete to authenticated
  using ((select auth.uid()) = user_id);

revoke update on public.post_likes from anon, authenticated;

create table public.comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts (id) on delete cascade,
  author_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  body text not null check (char_length(body) between 1 and 1000),
  created_at timestamptz not null default now()
);

create index comments_post_created_at_idx on public.comments (post_id, created_at);
create index comments_author_id_idx on public.comments (author_id);

alter table public.comments enable row level security;

create policy "Signed-in users can see comments"
  on public.comments for select to authenticated
  using (true);
create policy "Users comment as themselves"
  on public.comments for insert to authenticated
  with check ((select auth.uid()) = author_id);
create policy "Comment and post authors can delete comments"
  on public.comments for delete to authenticated
  using (
    (select auth.uid()) = author_id
    or (select auth.uid()) = (select p.author_id from public.posts p where p.id = post_id)
  );

revoke update on public.comments from anon, authenticated;

-- Like and comment counters.
create function public.bump_post_counts()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_table_name = 'post_likes' then
    if tg_op = 'INSERT' then
      update public.posts set like_count = like_count + 1 where id = new.post_id;
    else
      update public.posts set like_count = greatest(like_count - 1, 0) where id = old.post_id;
    end if;
  else
    if tg_op = 'INSERT' then
      update public.posts set comment_count = comment_count + 1 where id = new.post_id;
    else
      update public.posts set comment_count = greatest(comment_count - 1, 0) where id = old.post_id;
    end if;
  end if;
  return null;
end;
$$;

revoke execute on function public.bump_post_counts() from public, anon, authenticated;

create trigger post_likes_count
  after insert or delete on public.post_likes
  for each row execute function public.bump_post_counts();
create trigger comments_count
  after insert or delete on public.comments
  for each row execute function public.bump_post_counts();

-- Posts with their author and the viewer's like state.
create view public.feed_posts
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
  (p.ticker is not null and public.holds_ticker(p.author_id, p.ticker)) as author_holds_ticker
from public.posts p
join public.profiles pr on pr.id = p.author_id;

-- Profiles with counts and the viewer's follow state.
create view public.profile_stats
with (security_invoker = true)
as
select
  pr.id,
  pr.username,
  pr.display_name,
  pr.bio,
  pr.avatar_path,
  pr.share_portfolio,
  pr.created_at,
  (select count(*) from public.follows f where f.followee_id = pr.id)::integer as follower_count,
  (select count(*) from public.follows f where f.follower_id = pr.id)::integer as following_count,
  (select count(*) from public.posts p where p.author_id = pr.id)::integer as post_count,
  exists (
    select 1 from public.follows f
    where f.follower_id = (select auth.uid()) and f.followee_id = pr.id
  ) as followed_by_me
from public.profiles pr;

-- Comments with their author.
create view public.comment_details
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
join public.profiles pr on pr.id = c.author_id;

revoke all on public.feed_posts, public.profile_stats, public.comment_details from anon;
grant select on public.feed_posts, public.profile_stats, public.comment_details to authenticated;

-- Home feed. scope 'following' = you and people you follow; 'explore' = everyone.
-- Pass the created_at of the last post you have to get the next page.
create function public.get_feed(p_scope text default 'following', p_before timestamptz default null, p_limit integer default 20)
returns setof public.feed_posts
language sql
stable
security invoker
set search_path = ''
as $$
  select f.*
  from public.feed_posts f
  where (p_before is null or f.created_at < p_before)
    and (
      p_scope = 'explore'
      or f.author_id = (select auth.uid())
      or f.author_id in (select fo.followee_id from public.follows fo where fo.follower_id = (select auth.uid()))
    )
  order by f.created_at desc
  limit least(greatest(p_limit, 1), 50);
$$;

-- People search by username or display name.
create function public.search_profiles(p_query text, p_limit integer default 20)
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
  from public.profile_stats s, q
  where q.raw <> ''
    and (s.username ilike '%' || q.pattern || '%' or s.display_name ilike '%' || q.pattern || '%')
  order by (s.username = q.raw) desc, s.follower_count desc, s.username
  limit least(greatest(p_limit, 1), 50);
$$;

-- People to follow: popular profiles you don't follow yet.
create function public.suggested_profiles(p_limit integer default 20)
returns setof public.profile_stats
language sql
stable
security invoker
set search_path = ''
as $$
  select s.*
  from public.profile_stats s
  where s.id <> (select auth.uid()) and not s.followed_by_me
  order by s.follower_count desc, s.post_count desc, s.created_at desc
  limit least(greatest(p_limit, 1), 50);
$$;

-- Recent likes, comments and follows involving you, newest first.
create function public.get_activity(p_limit integer default 50)
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
  order by created_at desc
  limit least(greatest(p_limit, 1), 100);
$$;

revoke execute on function public.get_feed(text, timestamptz, integer) from public, anon;
revoke execute on function public.search_profiles(text, integer) from public, anon;
revoke execute on function public.suggested_profiles(integer) from public, anon;
revoke execute on function public.get_activity(integer) from public, anon;
grant execute on function public.get_feed(text, timestamptz, integer) to authenticated;
grant execute on function public.search_profiles(text, integer) to authenticated;
grant execute on function public.suggested_profiles(integer) to authenticated;
grant execute on function public.get_activity(integer) to authenticated;
