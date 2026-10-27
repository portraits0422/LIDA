-- LIDA production starter schema (Supabase / PostgreSQL)
-- Run in the Supabase SQL Editor after reviewing policies for your deployment.
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text not null unique check (username ~ '^[A-Za-z0-9_.]{3,24}$'),
  display_name text not null default '',
  avatar_path text,
  cover_path text,
  bio text not null default '' check (char_length(bio) <= 300),
  visibility text not null default 'public' check (visibility in ('public','private','contacts')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists profiles_username_lower_idx on public.profiles (lower(username));
create unique index if not exists profiles_username_lower_unique on public.profiles (lower(username));

create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
declare uname text;
begin
  uname := coalesce(new.raw_user_meta_data->>'username', 'user_' || substr(new.id::text,1,8));
  insert into public.profiles (id, username, display_name)
  values (new.id, uname, coalesce(new.raw_user_meta_data->>'display_name', uname))
  on conflict (id) do nothing;
  return new;
end;
$$;
drop trigger if exists on_auth_user_created_lida on auth.users;
create trigger on_auth_user_created_lida after insert on auth.users for each row execute procedure public.handle_new_user();

create table if not exists public.contacts (
  owner_id uuid not null references auth.users(id) on delete cascade,
  contact_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','accepted','blocked')),
  created_at timestamptz not null default now(),
  primary key (owner_id, contact_id), check (owner_id <> contact_id)
);

create table if not exists public.blocks (
  blocker_id uuid not null references auth.users(id) on delete cascade,
  blocked_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id), check (blocker_id <> blocked_id)
);

create table if not exists public.posts (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references auth.users(id) on delete cascade,
  body text not null default '' check (char_length(body) <= 10000),
  media_path text,
  media_type text check (media_type is null or media_type in ('image','video')),
  visibility text not null default 'public' check (visibility in ('public','contacts','private')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  check (body <> '' or media_path is not null)
);
create index if not exists posts_feed_idx on public.posts (created_at desc) where deleted_at is null;
create index if not exists posts_author_idx on public.posts (author_id, created_at desc);

create table if not exists public.post_reactions (
  post_id uuid not null references public.posts(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  reaction text not null default 'like' check (reaction in ('like','love','laugh','wow','sad','fire')),
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);
create table if not exists public.comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts(id) on delete cascade,
  author_id uuid not null references auth.users(id) on delete cascade,
  parent_id uuid references public.comments(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 4000),
  created_at timestamptz not null default now(),
  edited_at timestamptz,
  deleted_at timestamptz
);
create index if not exists comments_post_idx on public.comments (post_id, created_at);

create table if not exists public.statuses (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references auth.users(id) on delete cascade,
  body text not null default '',
  media_path text,
  media_type text check (media_type is null or media_type in ('image','video')),
  audience text not null default 'contacts' check (audience in ('contacts','exclude','selected')),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '24 hours'),
  check (expires_at <= created_at + interval '24 hours' and expires_at > created_at),
  check (body <> '' or media_path is not null)
);
create index if not exists statuses_live_idx on public.statuses (expires_at, created_at desc);
create table if not exists public.status_audience (
  status_id uuid not null references public.statuses(id) on delete cascade,
  viewer_id uuid not null references auth.users(id) on delete cascade,
  mode text not null check (mode in ('allow','exclude')),
  primary key (status_id, viewer_id)
);
create table if not exists public.status_views (
  status_id uuid not null references public.statuses(id) on delete cascade,
  viewer_id uuid not null references auth.users(id) on delete cascade,
  viewed_at timestamptz not null default now(),
  primary key (status_id, viewer_id)
);

create table if not exists public.conversations (
  id uuid primary key default gen_random_uuid(),
  kind text not null default 'direct' check (kind in ('direct','group')),
  title text,
  created_by uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  message_ttl_seconds integer check (message_ttl_seconds is null or message_ttl_seconds between 60 and 31536000)
);
create table if not exists public.conversation_members (
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'member' check (role in ('owner','admin','member')),
  joined_at timestamptz not null default now(),
  archived_at timestamptz,
  pinned_at timestamptz,
  muted_until timestamptz,
  last_read_at timestamptz,
  primary key (conversation_id, user_id)
);
create index if not exists conversation_members_user_idx on public.conversation_members (user_id, pinned_at desc, joined_at desc);
create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  body text not null default '',
  message_type text not null default 'text' check (message_type in ('text','image','video','file','audio','location','sticker','system')),
  media_path text,
  media_mime text,
  reply_to uuid references public.messages(id) on delete set null,
  created_at timestamptz not null default now(),
  edited_at timestamptz,
  expires_at timestamptz,
  deleted_at timestamptz,
  delivered_at timestamptz,
  check (body <> '' or media_path is not null or message_type = 'system')
);
create index if not exists messages_conversation_idx on public.messages (conversation_id, created_at desc);
create index if not exists messages_expiration_idx on public.messages (expires_at) where expires_at is not null;
create or replace function public.apply_message_expiration() returns trigger language plpgsql security definer set search_path = public as $$
declare ttl integer;
begin
  select c.message_ttl_seconds into ttl from public.conversations c where c.id = new.conversation_id;
  if ttl is not null then new.expires_at := new.created_at + make_interval(secs => ttl); end if;
  return new;
end;
$$;
drop trigger if exists messages_set_expiration on public.messages;
create trigger messages_set_expiration before insert on public.messages for each row execute procedure public.apply_message_expiration();
create table if not exists public.message_reactions (
  message_id uuid not null references public.messages(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  reaction text not null,
  created_at timestamptz not null default now(),
  primary key (message_id, user_id)
);
create table if not exists public.message_receipts (
  message_id uuid not null references public.messages(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  delivered_at timestamptz,
  read_at timestamptz,
  primary key (message_id, user_id)
);

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  actor_id uuid references auth.users(id) on delete set null,
  kind text not null check (kind in ('chat','community','mention','contact','game','system','call')),
  title text not null,
  body text not null default '',
  target_type text,
  target_id uuid,
  read_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists notifications_user_idx on public.notifications (user_id, created_at desc);

create table if not exists public.reels (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references auth.users(id) on delete cascade,
  video_path text not null,
  thumbnail_path text,
  caption text not null default '' check (char_length(caption) <= 3000),
  visibility text not null default 'public' check (visibility in ('public','contacts','private')),
  created_at timestamptz not null default now(),
  deleted_at timestamptz
);
create index if not exists reels_feed_idx on public.reels (created_at desc) where deleted_at is null;
create table if not exists public.reel_reactions (
  reel_id uuid not null references public.reels(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (reel_id, user_id)
);
create table if not exists public.saved_items (
  user_id uuid not null references auth.users(id) on delete cascade,
  item_type text not null check (item_type in ('post','reel','game','message')),
  item_id uuid not null,
  created_at timestamptz not null default now(),
  primary key (user_id, item_type, item_id)
);

create table if not exists public.games (
  id uuid primary key default gen_random_uuid(),
  added_by uuid references auth.users(id) on delete set null,
  name text not null,
  description text not null default '',
  category text not null default 'Casual',
  launch_url text not null,
  thumbnail_path text,
  license_url text,
  is_verified boolean not null default false,
  created_at timestamptz not null default now()
);
create table if not exists public.game_favorites (
  user_id uuid not null references auth.users(id) on delete cascade,
  game_id uuid not null references public.games(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, game_id)
);
create table if not exists public.game_challenges (
  id uuid primary key default gen_random_uuid(),
  creator_id uuid not null references auth.users(id) on delete cascade,
  invited_user_id uuid references auth.users(id) on delete set null,
  game_id uuid references public.games(id) on delete set null,
  status text not null default 'pending' check (status in ('pending','accepted','declined','completed','cancelled')),
  score_creator integer,
  score_invited integer,
  created_at timestamptz not null default now(),
  completed_at timestamptz
);

create table if not exists public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references auth.users(id) on delete cascade,
  target_type text not null check (target_type in ('profile','post','comment','status','message','reel','game')),
  target_id uuid not null,
  reason text not null check (char_length(reason) between 2 and 2000),
  status text not null default 'open' check (status in ('open','reviewing','resolved','dismissed')),
  created_at timestamptz not null default now()
);
create table if not exists public.user_preferences (
  user_id uuid primary key references auth.users(id) on delete cascade,
  preferences jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);
create table if not exists public.call_signals (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  from_user uuid not null references auth.users(id) on delete cascade,
  to_user uuid not null references auth.users(id) on delete cascade,
  signal_type text not null check (signal_type in ('offer','answer','ice','ring','accept','decline','end','busy')),
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '5 minutes'
);
create index if not exists call_signals_expiry_idx on public.call_signals (expires_at);

-- Updated-at helper
create or replace function public.set_updated_at() returns trigger language plpgsql as $$ begin new.updated_at = now(); return new; end; $$;
drop trigger if exists profiles_updated_at on public.profiles;
create trigger profiles_updated_at before update on public.profiles for each row execute procedure public.set_updated_at();
drop trigger if exists posts_updated_at on public.posts;
create trigger posts_updated_at before update on public.posts for each row execute procedure public.set_updated_at();

-- SECURITY DEFINER membership helpers prevent recursive RLS policies on conversation_members/status_audience.
create or replace function public.is_conversation_member(conversation_id_input uuid, user_id_input uuid default auth.uid()) returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.conversation_members m where m.conversation_id = conversation_id_input and m.user_id = user_id_input);
$$;
create or replace function public.is_conversation_creator(conversation_id_input uuid, user_id_input uuid default auth.uid()) returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.conversations c where c.id = conversation_id_input and c.created_by = user_id_input);
$$;
create or replace function public.is_status_owner(status_id_input uuid, user_id_input uuid default auth.uid()) returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.statuses s where s.id = status_id_input and s.author_id = user_id_input);
$$;
revoke all on function public.is_conversation_member(uuid, uuid) from public, anon;
revoke all on function public.is_status_owner(uuid, uuid) from public, anon;
revoke all on function public.is_conversation_creator(uuid, uuid) from public, anon;
grant execute on function public.is_conversation_member(uuid, uuid) to authenticated;
grant execute on function public.is_status_owner(uuid, uuid) to authenticated;
grant execute on function public.is_conversation_creator(uuid, uuid) to authenticated;

-- RLS is enabled on all user data. Policies below are a secure baseline, not a substitute for a final security review.
alter table public.profiles enable row level security;
alter table public.contacts enable row level security;
alter table public.blocks enable row level security;
alter table public.posts enable row level security;
alter table public.post_reactions enable row level security;
alter table public.comments enable row level security;
alter table public.statuses enable row level security;
alter table public.status_audience enable row level security;
alter table public.status_views enable row level security;
alter table public.conversations enable row level security;
alter table public.conversation_members enable row level security;
alter table public.messages enable row level security;
alter table public.message_reactions enable row level security;
alter table public.message_receipts enable row level security;
alter table public.notifications enable row level security;
alter table public.reels enable row level security;
alter table public.reel_reactions enable row level security;
alter table public.saved_items enable row level security;
alter table public.games enable row level security;
alter table public.game_favorites enable row level security;
alter table public.game_challenges enable row level security;
alter table public.reports enable row level security;
alter table public.user_preferences enable row level security;
alter table public.call_signals enable row level security;

-- Profiles: public-safe fields only; never store public email here.
create policy "Profiles visible by visibility" on public.profiles for select to authenticated using (
  visibility = 'public' or id = auth.uid() or
  (visibility = 'contacts' and exists(select 1 from public.contacts c where c.owner_id = auth.uid() and c.contact_id = id and c.status = 'accepted'))
);
create policy "Users insert own profile" on public.profiles for insert to authenticated with check (id = auth.uid());
create policy "Users update own profile" on public.profiles for update to authenticated using (id = auth.uid()) with check (id = auth.uid());
create policy "Contacts participants read" on public.contacts for select to authenticated using (owner_id = auth.uid() or contact_id = auth.uid());
create policy "Users manage own contacts" on public.contacts for all to authenticated using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy "Recipients accept contact requests" on public.contacts for update to authenticated using (contact_id = auth.uid()) with check (contact_id = auth.uid() and status in ('accepted','blocked'));
create policy "Block list private" on public.blocks for select to authenticated using (blocker_id = auth.uid());
create policy "Users manage own blocks" on public.blocks for all to authenticated using (blocker_id = auth.uid()) with check (blocker_id = auth.uid());

create policy "Public posts readable" on public.posts for select to authenticated using (deleted_at is null and (visibility = 'public' or author_id = auth.uid() or (visibility = 'contacts' and exists(select 1 from public.contacts c where c.owner_id = author_id and c.contact_id = auth.uid() and c.status = 'accepted'))));
create policy "Users create own posts" on public.posts for insert to authenticated with check (author_id = auth.uid());
create policy "Authors update own posts" on public.posts for update to authenticated using (author_id = auth.uid()) with check (author_id = auth.uid());
create policy "Authors delete own posts" on public.posts for delete to authenticated using (author_id = auth.uid());
create policy "Reactions visible with post" on public.post_reactions for select to authenticated using (exists(select 1 from public.posts p where p.id = post_id and p.deleted_at is null));
create policy "Users manage own reactions" on public.post_reactions for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "Comments visible with post" on public.comments for select to authenticated using (exists(select 1 from public.posts p where p.id = post_id and p.deleted_at is null));
create policy "Users create comments" on public.comments for insert to authenticated with check (author_id = auth.uid());
create policy "Authors manage comments" on public.comments for update using (author_id = auth.uid()) with check (author_id = auth.uid());
create policy "Authors delete comments" on public.comments for delete using (author_id = auth.uid());

-- Status policy enforces 24h expiry and audience. For selected/excluded audiences, rows are in status_audience.
create policy "Status owner or authorized audience" on public.statuses for select to authenticated using (
  author_id = auth.uid() or (expires_at > now() and audience = 'contacts' and exists(select 1 from public.contacts c where c.owner_id = author_id and c.contact_id = auth.uid() and c.status = 'accepted')) or
  (expires_at > now() and audience = 'selected' and exists(select 1 from public.status_audience a where a.status_id = id and a.viewer_id = auth.uid() and a.mode = 'allow')) or
  (expires_at > now() and audience = 'exclude' and not exists(select 1 from public.status_audience a where a.status_id = id and a.viewer_id = auth.uid() and a.mode = 'exclude') and exists(select 1 from public.contacts c where c.owner_id = author_id and c.contact_id = auth.uid() and c.status = 'accepted'))
);
create policy "Users create own statuses" on public.statuses for insert to authenticated with check (author_id = auth.uid() and expires_at <= now() + interval '24 hours');
create policy "Owners manage own statuses" on public.statuses for update to authenticated using (author_id = auth.uid()) with check (author_id = auth.uid() and expires_at <= created_at + interval '24 hours' and expires_at > created_at);
create policy "Owners delete own statuses" on public.statuses for delete to authenticated using (author_id = auth.uid());
create policy "Status audience owner manages" on public.status_audience for all to authenticated using (public.is_status_owner(status_id, auth.uid())) with check (public.is_status_owner(status_id, auth.uid()));
create policy "Status audience visible to owner or viewer" on public.status_audience for select to authenticated using (public.is_status_owner(status_id, auth.uid()) or viewer_id = auth.uid());
create policy "Status views visible to owner or viewer" on public.status_views for select to authenticated using (viewer_id = auth.uid() or exists(select 1 from public.statuses s where s.id = status_id and s.author_id = auth.uid()));
create policy "Viewers record own views" on public.status_views for insert to authenticated with check (viewer_id = auth.uid() and exists(select 1 from public.statuses s where s.id = status_id));

create policy "Conversation members read conversations" on public.conversations for select to authenticated using (public.is_conversation_member(id, auth.uid()));
create policy "Authenticated users create conversations" on public.conversations for insert to authenticated with check (created_by = auth.uid());
create policy "Conversation members update conversations" on public.conversations for update to authenticated using (public.is_conversation_member(id, auth.uid())) with check (public.is_conversation_member(id, auth.uid()));
create policy "Members can see own membership" on public.conversation_members for select to authenticated using (user_id = auth.uid() or public.is_conversation_member(conversation_id, auth.uid()));
create policy "Conversation creator adds members" on public.conversation_members for insert to authenticated with check (user_id = auth.uid() or public.is_conversation_creator(conversation_id, auth.uid()));
create policy "Users update own membership settings" on public.conversation_members for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "Conversation members read messages" on public.messages for select to authenticated using (public.is_conversation_member(conversation_id, auth.uid()) and (expires_at is null or expires_at > now()));
create policy "Members send own messages" on public.messages for insert to authenticated with check (sender_id = auth.uid() and public.is_conversation_member(conversation_id, auth.uid()));
create policy "Senders edit own messages" on public.messages for update to authenticated using (sender_id = auth.uid() and public.is_conversation_member(conversation_id, auth.uid())) with check (sender_id = auth.uid() and public.is_conversation_member(conversation_id, auth.uid()));
create policy "Senders delete own messages" on public.messages for delete to authenticated using (sender_id = auth.uid() and public.is_conversation_member(conversation_id, auth.uid()));
create policy "Message reactions visible to members" on public.message_reactions for select to authenticated using (exists(select 1 from public.messages m where m.id = message_id and public.is_conversation_member(m.conversation_id, auth.uid())));
create policy "Users manage own message reactions" on public.message_reactions for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "Receipts visible to conversation members" on public.message_receipts for select to authenticated using (user_id = auth.uid() or exists(select 1 from public.messages m where m.id = message_id and public.is_conversation_member(m.conversation_id, auth.uid())));
create policy "Users manage own receipts" on public.message_receipts for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "Notifications private to owner" on public.notifications for select to authenticated using (user_id = auth.uid());
create policy "Notifications update private to owner" on public.notifications for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "Reels public or author readable" on public.reels for select to authenticated using (deleted_at is null and (visibility = 'public' or author_id = auth.uid() or (visibility = 'contacts' and exists(select 1 from public.contacts c where c.owner_id = author_id and c.contact_id = auth.uid() and c.status = 'accepted'))));
create policy "Users create own reels" on public.reels for insert to authenticated with check (author_id = auth.uid());
create policy "Authors update own reels" on public.reels for update to authenticated using (author_id = auth.uid()) with check (author_id = auth.uid());
create policy "Authors delete own reels" on public.reels for delete to authenticated using (author_id = auth.uid());
create policy "Reel reactions readable" on public.reel_reactions for select to authenticated using (exists(select 1 from public.reels r where r.id = reel_id and r.deleted_at is null));
create policy "Users manage own reel reactions" on public.reel_reactions for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "Saved items private" on public.saved_items for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "Verified games readable" on public.games for select to authenticated using (is_verified or added_by = auth.uid());
create policy "Users submit games for review" on public.games for insert to authenticated with check (added_by = auth.uid() and is_verified = false);
create policy "Game favorites private" on public.game_favorites for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "Challenge participants read" on public.game_challenges for select to authenticated using (creator_id = auth.uid() or invited_user_id = auth.uid());
create policy "Users create challenges" on public.game_challenges for insert to authenticated with check (creator_id = auth.uid());
create policy "Invitees update challenge" on public.game_challenges for update to authenticated using (creator_id = auth.uid() or invited_user_id = auth.uid()) with check (creator_id = auth.uid() or invited_user_id = auth.uid());
create policy "Reporters create reports" on public.reports for insert to authenticated with check (reporter_id = auth.uid());
create policy "Reporters read own reports" on public.reports for select to authenticated using (reporter_id = auth.uid());
create policy "Preferences private to owner" on public.user_preferences for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "Call signals participants read" on public.call_signals for select to authenticated using (from_user = auth.uid() or to_user = auth.uid());
create policy "Call participants send signals" on public.call_signals for insert to authenticated with check (from_user = auth.uid() and public.is_conversation_member(conversation_id, auth.uid()));
create policy "Call senders remove signals" on public.call_signals for delete to authenticated using (from_user = auth.uid() or to_user = auth.uid());

-- Optional cleanup: schedule this function with pg_cron if enabled in your Supabase project.
create or replace function public.cleanup_expired_lida_content() returns void
language plpgsql security definer set search_path = public as $$
begin
  delete from public.statuses where expires_at <= now();
  delete from public.messages where expires_at is not null and expires_at <= now();
  delete from public.call_signals where expires_at <= now();
end;
$$;
revoke all on function public.cleanup_expired_lida_content() from public, anon, authenticated;

-- Storage buckets. Add bucket-specific policies after reviewing file size/type limits for your deployment.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('lida-avatars','lida-avatars', true, 5242880, array['image/jpeg','image/png','image/webp']),
  ('lida-community','lida-community', false, 41943040, array['image/jpeg','image/png','image/webp','video/mp4','video/webm']),
  ('lida-chat','lida-chat', false, 52428800, array['image/jpeg','image/png','image/webp','video/mp4','video/webm','audio/webm','audio/ogg','application/pdf','text/plain']),
  ('lida-reels','lida-reels', false, 83886080, array['video/mp4','video/webm','image/jpeg','image/png'])
on conflict (id) do nothing;

-- NOTE: Enable Realtime for messages, notifications, conversation_members, call_signals and relevant feeds in Supabase Dashboard.
-- NOTE: For a fully secure deployment, add/verify Storage object policies, rate limiting, moderation workflow,
-- pg_cron expiration schedule, backups, SMTP, TURN credentials, and an independent RLS security review.

-- Storage object path conventions:
-- avatars: <auth.uid()>/<filename>; community/reels: <auth.uid()>/<filename>; chat: <conversation_uuid>/<auth.uid()>/<filename>.
create policy "Avatar images are publicly readable" on storage.objects for select to public using (bucket_id = 'lida-avatars');
create policy "Users upload own avatar files" on storage.objects for insert to authenticated with check (bucket_id = 'lida-avatars' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "Users update own avatar files" on storage.objects for update to authenticated using (bucket_id = 'lida-avatars' and (storage.foldername(name))[1] = auth.uid()::text) with check (bucket_id = 'lida-avatars' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "Users delete own avatar files" on storage.objects for delete to authenticated using (bucket_id = 'lida-avatars' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "Users upload own community media" on storage.objects for insert to authenticated with check (bucket_id = 'lida-community' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "Owners manage own community media" on storage.objects for all to authenticated using (bucket_id = 'lida-community' and (storage.foldername(name))[1] = auth.uid()::text) with check (bucket_id = 'lida-community' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "Users upload own reels" on storage.objects for insert to authenticated with check (bucket_id = 'lida-reels' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "Owners manage own reels" on storage.objects for all to authenticated using (bucket_id = 'lida-reels' and (storage.foldername(name))[1] = auth.uid()::text) with check (bucket_id = 'lida-reels' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "Conversation members read chat media" on storage.objects for select to authenticated using (bucket_id = 'lida-chat' and public.is_conversation_member((storage.foldername(name))[1]::uuid, auth.uid()));
create policy "Members upload own chat media" on storage.objects for insert to authenticated with check (bucket_id = 'lida-chat' and public.is_conversation_member((storage.foldername(name))[1]::uuid, auth.uid()) and (storage.foldername(name))[2] = auth.uid()::text);
create policy "Owners delete own chat media" on storage.objects for delete to authenticated using (bucket_id = 'lida-chat' and (storage.foldername(name))[2] = auth.uid()::text and public.is_conversation_member((storage.foldername(name))[1]::uuid, auth.uid()));
