-- =====================================================
-- DOVERSUS LOG - Duomenų bazės struktūra
-- Vykdyti Supabase SQL Editor
-- =====================================================

-- Vartotojai (papildo Supabase auth.users)
create table public.profiles (
  id uuid references auth.users(id) on delete cascade primary key,
  full_name text not null,
  role text not null check (role in ('montuotojas','darbo-vadovas','vadovas')),
  color text default '#2E7EC7',
  initials text,
  created_at timestamptz default now()
);

-- Objektai
create table public.objects (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  address text,
  lat double precision,
  lng double precision,
  created_by uuid references public.profiles(id),
  created_at timestamptz default now(),
  is_active boolean default true
);

-- Objektų priskyrimas darbų vadovams
create table public.object_supervisors (
  object_id uuid references public.objects(id) on delete cascade,
  supervisor_id uuid references public.profiles(id) on delete cascade,
  assigned_at timestamptz default now(),
  primary key (object_id, supervisor_id)
);

-- Objektų priskyrimas montuotojams
create table public.object_workers (
  object_id uuid references public.objects(id) on delete cascade,
  worker_id uuid references public.profiles(id) on delete cascade,
  assigned_at timestamptz default now(),
  primary key (object_id, worker_id)
);

-- Darbo tipai
create table public.work_types (
  id text primary key,
  name text not null,
  icon text,
  unit text not null
);

insert into public.work_types (id, name, icon, unit) values
  ('kabelis', 'Kabelių klojimas', '🔌', 'm'),
  ('lizdai', 'Kišt. lizdai', '🔲', 'vnt'),
  ('sviestuvai', 'Šviestuvai', '💡', 'vnt'),
  ('trasa', 'Kab. trasa', '📦', 'm'),
  ('internet', 'Interneto kab.', '🌐', 'm'),
  ('signalizacija', 'Signalizacija', '🚨', 'vnt');

-- Normatyvai (minutės vienam vienetui)
create table public.norms (
  work_type_id text references public.work_types(id) primary key,
  minutes_per_unit double precision not null default 0,
  updated_by uuid references public.profiles(id),
  updated_at timestamptz default now()
);

insert into public.norms (work_type_id, minutes_per_unit) values
  ('kabelis', 5),
  ('lizdai', 30),
  ('sviestuvai', 45),
  ('trasa', 8),
  ('internet', 4),
  ('signalizacija', 25);

-- Darbo sesijos (GPS pradžia/pabaiga)
create table public.work_sessions (
  id uuid primary key default gen_random_uuid(),
  worker_id uuid references public.profiles(id) on delete cascade,
  object_id uuid references public.objects(id) on delete cascade,
  started_at timestamptz default now(),
  ended_at timestamptz,
  duration_hrs double precision
);

-- Darbų žurnalas
create table public.work_logs (
  id uuid primary key default gen_random_uuid(),
  worker_id uuid references public.profiles(id) on delete cascade,
  object_id uuid references public.objects(id) on delete cascade,
  session_id uuid references public.work_sessions(id),
  work_type_id text references public.work_types(id),
  qty double precision not null,
  hrs double precision not null,
  notes text,
  photo_urls text[],
  colleagues uuid[],
  corrected boolean default false,
  corrected_by uuid references public.profiles(id),
  corrected_at timestamptz,
  log_date date default current_date,
  created_at timestamptz default now()
);

-- Medžiagos objekte
create table public.materials (
  id uuid primary key default gen_random_uuid(),
  object_id uuid references public.objects(id) on delete cascade,
  work_type_id text references public.work_types(id),
  qty double precision not null,
  delivered_by uuid references public.profiles(id),
  delivery_date date default current_date,
  notes text,
  created_at timestamptz default now()
);

-- Mėnesiniai priedai
create table public.bonuses (
  id uuid primary key default gen_random_uuid(),
  worker_id uuid references public.profiles(id),
  month date not null,
  fact_hrs double precision default 0,
  norm_hrs double precision default 0,
  saved_hrs double precision default 0,
  bonus_hrs double precision default 0,
  bonus_pct double precision default 2,
  approved boolean default false,
  approved_by uuid references public.profiles(id),
  created_at timestamptz default now(),
  unique(worker_id, month)
);

-- =====================================================
-- ROW LEVEL SECURITY
-- =====================================================

alter table public.profiles enable row level security;
alter table public.objects enable row level security;
alter table public.object_supervisors enable row level security;
alter table public.object_workers enable row level security;
alter table public.work_types enable row level security;
alter table public.norms enable row level security;
alter table public.work_sessions enable row level security;
alter table public.work_logs enable row level security;
alter table public.materials enable row level security;
alter table public.bonuses enable row level security;

-- Profiles
create policy "Profiles readable by all authenticated" on public.profiles for select to authenticated using (true);
create policy "Profiles insertable by owner" on public.profiles for insert to authenticated with check (auth.uid() = id);
create policy "Profiles updatable by owner" on public.profiles for update to authenticated using (auth.uid() = id);

-- Objects
create policy "Objects readable" on public.objects for select to authenticated using (true);
create policy "Objects manageable by vadovas" on public.objects for all to authenticated using (
  exists (select 1 from public.profiles where id = auth.uid() and role = 'vadovas')
);

-- Object assignments
create policy "Object supervisors readable" on public.object_supervisors for select to authenticated using (true);
create policy "Object supervisors manageable" on public.object_supervisors for all to authenticated using (
  exists (select 1 from public.profiles where id = auth.uid() and role in ('vadovas'))
);
create policy "Object workers readable" on public.object_workers for select to authenticated using (true);
create policy "Object workers manageable" on public.object_workers for all to authenticated using (
  exists (select 1 from public.profiles where id = auth.uid() and role in ('vadovas','darbo-vadovas'))
);

-- Work types & norms
create policy "Work types readable" on public.work_types for select to authenticated using (true);
create policy "Norms readable" on public.norms for select to authenticated using (true);
create policy "Norms manageable by vadovas" on public.norms for all to authenticated using (
  exists (select 1 from public.profiles where id = auth.uid() and role = 'vadovas')
);

-- Work sessions
create policy "Sessions readable" on public.work_sessions for select to authenticated using (
  worker_id = auth.uid() or
  exists (select 1 from public.profiles where id = auth.uid() and role in ('vadovas','darbo-vadovas'))
);
create policy "Sessions insertable by worker" on public.work_sessions for insert to authenticated with check (worker_id = auth.uid());
create policy "Sessions updatable by worker" on public.work_sessions for update to authenticated using (worker_id = auth.uid());

-- Work logs
create policy "Logs readable" on public.work_logs for select to authenticated using (
  worker_id = auth.uid() or
  exists (select 1 from public.profiles where id = auth.uid() and role in ('vadovas','darbo-vadovas'))
);
create policy "Logs insertable" on public.work_logs for insert to authenticated with check (
  worker_id = auth.uid() or
  exists (select 1 from public.profiles where id = auth.uid() and role in ('vadovas','darbo-vadovas'))
);
create policy "Logs updatable by supervisor" on public.work_logs for update to authenticated using (
  worker_id = auth.uid() or
  exists (select 1 from public.profiles where id = auth.uid() and role in ('vadovas','darbo-vadovas'))
);
create policy "Logs deletable by supervisor" on public.work_logs for delete to authenticated using (
  exists (select 1 from public.profiles where id = auth.uid() and role in ('vadovas','darbo-vadovas'))
);

-- Materials
create policy "Materials readable" on public.materials for select to authenticated using (true);
create policy "Materials manageable by supervisor" on public.materials for all to authenticated using (
  exists (select 1 from public.profiles where id = auth.uid() and role in ('vadovas','darbo-vadovas'))
);

-- Bonuses
create policy "Bonuses readable" on public.bonuses for select to authenticated using (
  worker_id = auth.uid() or
  exists (select 1 from public.profiles where id = auth.uid() and role in ('vadovas'))
);
create policy "Bonuses manageable by vadovas" on public.bonuses for all to authenticated using (
  exists (select 1 from public.profiles where id = auth.uid() and role = 'vadovas')
);

-- =====================================================
-- STORAGE (nuotraukoms)
-- =====================================================
insert into storage.buckets (id, name, public) values ('work-photos', 'work-photos', false);

create policy "Photos uploadable by workers" on storage.objects for insert to authenticated with check (bucket_id = 'work-photos');
create policy "Photos readable by authenticated" on storage.objects for select to authenticated using (bucket_id = 'work-photos');

-- =====================================================
-- TRIGGER: auto-create profile after signup
-- =====================================================
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer as $$
begin
  insert into public.profiles (id, full_name, role, initials, color)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', new.email),
    coalesce(new.raw_user_meta_data->>'role', 'montuotojas'),
    coalesce(new.raw_user_meta_data->>'initials', upper(left(coalesce(new.raw_user_meta_data->>'full_name', 'XX'), 2))),
    coalesce(new.raw_user_meta_data->>'color', '#2E7EC7')
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
