-- holds_ticker is only needed by the feed_posts view, so move it out of the
-- API-exposed public schema. (public_portfolio and public_portfolio_summary
-- stay public on purpose: the app calls them, they honor share_portfolio,
-- and they return percentages only.)

create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated;

alter function public.holds_ticker(uuid, text) set schema private;
revoke execute on function private.holds_ticker(uuid, text) from public, anon;
grant execute on function private.holds_ticker(uuid, text) to authenticated;

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
join public.profiles pr on pr.id = p.author_id;
