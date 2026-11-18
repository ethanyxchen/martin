create table public.records (
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  kind text not null check (kind in ('meeting', 'project')),
  id text not null,
  data jsonb,
  edited_at timestamptz not null,
  updated_at timestamptz not null default clock_timestamp(),
  primary key (user_id, kind, id)
);

create index records_user_id_updated_at on public.records (user_id, updated_at);

alter table public.records enable row level security;

create policy "Owners read their records" on public.records
  for select to authenticated using ((select auth.uid()) = user_id);

create policy "Owners add their records" on public.records
  for insert to authenticated with check ((select auth.uid()) = user_id);

create policy "Owners change their records" on public.records
  for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

create function public.keep_latest_edit() returns trigger
  language plpgsql
  set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' and new.edited_at < old.edited_at then
    return null;
  end if;
  new.updated_at := clock_timestamp();
  return new;
end;
$$;

create trigger keep_latest_edit
  before insert or update on public.records
  for each row execute function public.keep_latest_edit();

insert into storage.buckets (id, name, public) values ('images', 'images', false);

create policy "Owners read their images" on storage.objects
  for select to authenticated using (bucket_id = 'images' and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy "Owners add their images" on storage.objects
  for insert to authenticated with check (bucket_id = 'images' and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy "Owners change their images" on storage.objects
  for update to authenticated using (bucket_id = 'images' and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy "Owners remove their images" on storage.objects
  for delete to authenticated using (bucket_id = 'images' and (storage.foldername(name))[1] = (select auth.uid())::text);
