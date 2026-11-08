-- Public image buckets. Anyone with a URL can view images; users can only
-- write inside a folder named after their user id ("<user id>/<file>").

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('avatars', 'avatars', true, 5242880, array['image/jpeg', 'image/png', 'image/heic']),
  ('post-images', 'post-images', true, 10485760, array['image/jpeg', 'image/png', 'image/heic'])
on conflict (id) do nothing;

create policy "Users upload images to their own folder"
  on storage.objects for insert to authenticated
  with check (
    bucket_id in ('avatars', 'post-images')
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy "Users update images in their own folder"
  on storage.objects for update to authenticated
  using (
    bucket_id in ('avatars', 'post-images')
    and (storage.foldername(name))[1] = (select auth.uid())::text
  )
  with check (
    bucket_id in ('avatars', 'post-images')
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy "Users delete images in their own folder"
  on storage.objects for delete to authenticated
  using (
    bucket_id in ('avatars', 'post-images')
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );
