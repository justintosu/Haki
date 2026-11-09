-- Haki — daily limits for the "haki-ai" edge function (assistant chat,
-- clothing tags, outfit ideas, flashcards from notes). Same counters as the
-- food features (public.ai_usage); only the allowed kinds grow.

alter table public.ai_usage drop constraint if exists ai_usage_kind_check;

alter table public.ai_usage
  add constraint ai_usage_kind_check
  check (kind in ('meal', 'menu', 'chat', 'clothing', 'outfit', 'flashcards'));

comment on table public.ai_usage is
  'Daily AI request counts per user and kind; written only by the food-ai and haki-ai edge functions.';
