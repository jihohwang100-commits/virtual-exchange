-- Virtual Exchange v2: run in a NEW Supabase project, or carefully migrate an existing test project.
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default 'Trader',
  role text not null default 'user' check (role in ('user','admin')),
  created_at timestamptz not null default now()
);
create table if not exists public.accounts (
  user_id uuid primary key references auth.users(id) on delete cascade,
  cash bigint not null default 300000 check (cash >= 0),
  created_at timestamptz not null default now()
);
create table if not exists public.stocks (
  id uuid primary key default gen_random_uuid(),
  symbol text unique not null,
  name text not null,
  current_price bigint not null check (current_price > 0),
  tick_size bigint not null default 10 check (tick_size = 10),
  total_shares bigint not null default 10000 check (total_shares > 0),
  created_at timestamptz not null default now()
);
create table if not exists public.positions (
  user_id uuid not null references auth.users(id) on delete cascade,
  stock_id uuid not null references public.stocks(id) on delete cascade,
  quantity bigint not null default 0 check (quantity >= 0),
  primary key (user_id, stock_id)
);
create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  stock_id uuid not null references public.stocks(id),
  side text not null check (side in ('buy','sell')),
  limit_price bigint not null check (limit_price > 0 and limit_price % 10 = 0),
  quantity bigint not null check (quantity > 0),
  filled_quantity bigint not null default 0 check (filled_quantity >= 0 and filled_quantity <= quantity),
  status text not null default 'open' check (status in ('open','partial','filled','cancelled','rejected')),
  created_at timestamptz not null default now()
);
create table if not exists public.trades (
  id uuid primary key default gen_random_uuid(),
  stock_id uuid not null references public.stocks(id),
  buyer_id uuid not null references auth.users(id),
  seller_id uuid not null references auth.users(id),
  price bigint not null check (price > 0 and price % 10 = 0),
  quantity bigint not null check (quantity > 0),
  created_at timestamptz not null default now(),
  check (buyer_id <> seller_id)
);
create table if not exists public.price_history (
  id bigint generated always as identity primary key,
  stock_id uuid not null references public.stocks(id) on delete cascade,
  price bigint not null check (price > 0 and price % 10 = 0),
  recorded_at timestamptz not null default now()
);
create table if not exists public.news (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(title) between 1 and 120),
  body text not null check (char_length(body) between 1 and 5000),
  published boolean not null default true,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

create index if not exists orders_book_idx on public.orders(stock_id,status,side,limit_price,created_at);
create index if not exists orders_user_idx on public.orders(user_id,created_at desc);
create index if not exists trades_stock_idx on public.trades(stock_id,created_at desc);
create index if not exists news_created_idx on public.news(created_at desc);

alter table public.profiles enable row level security;
alter table public.accounts enable row level security;
alter table public.stocks enable row level security;
alter table public.positions enable row level security;
alter table public.orders enable row level security;
alter table public.trades enable row level security;
alter table public.price_history enable row level security;
alter table public.news enable row level security;

drop policy if exists "profiles read own" on public.profiles;
create policy "profiles read own" on public.profiles for select to authenticated using (id=auth.uid());
drop policy if exists "profiles update own" on public.profiles;
create policy "profiles update own" on public.profiles for update to authenticated using (id=auth.uid()) with check (id=auth.uid() and role='user');
drop policy if exists "accounts read own" on public.accounts;
create policy "accounts read own" on public.accounts for select to authenticated using (user_id=auth.uid());
drop policy if exists "positions read own" on public.positions;
create policy "positions read own" on public.positions for select to authenticated using (user_id=auth.uid());
drop policy if exists "orders read own" on public.orders;
create policy "orders read own" on public.orders for select to authenticated using (user_id=auth.uid());
drop policy if exists "trades read participants" on public.trades;
create policy "trades read participants" on public.trades for select to authenticated using (buyer_id=auth.uid() or seller_id=auth.uid());
drop policy if exists "stocks read all" on public.stocks;
create policy "stocks read all" on public.stocks for select to authenticated using (true);
drop policy if exists "price history read all" on public.price_history;
create policy "price history read all" on public.price_history for select to authenticated using (true);
drop policy if exists "published news read" on public.news;
create policy "published news read" on public.news for select to authenticated using (published=true);

-- Set this to the email address the creator will use to sign up, before creator signup.
create table if not exists public.exchange_settings (
  setting_key text primary key,
  setting_value text not null
);
insert into public.exchange_settings(setting_key,setting_value)
values ('creator_email','creator@example.com')
on conflict(setting_key) do nothing;

-- Six fictional companies, with ASTR the initial founder-owned 10,000-share company.
insert into public.stocks(symbol,name,current_price,tick_size,total_shares) values
 ('ASTR','Aster Robotics',1500,10,10000),
 ('NOVA','Nova Energy',18400,10,10000),
 ('MINT','Mint BioLabs',32600,10,10000),
 ('ORBT','Orbit Mobility',12700,10,10000),
 ('LUMI','Lumi Semicon',48100,10,10000),
 ('WAVE','Wave Media',9600,10,10000)
on conflict(symbol) do update set current_price=excluded.current_price, tick_size=10, total_shares=excluded.total_shares;

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path=public
as $$
declare v_stock uuid; v_creator_email text;
begin
  select setting_value into v_creator_email from public.exchange_settings where setting_key='creator_email';
  insert into public.profiles(id,display_name,role)
  values(new.id,coalesce(nullif(split_part(new.email,'@',1),''),'Trader'),
    case when lower(coalesce(new.email,''))=lower(coalesce(v_creator_email,'')) then 'admin' else 'user' end)
  on conflict(id) do nothing;
  insert into public.accounts(user_id,cash) values(new.id,300000) on conflict(user_id) do nothing;
  if lower(coalesce(new.email,''))=lower(coalesce(v_creator_email,'')) then
    select id into v_stock from public.stocks where symbol='ASTR';
    if v_stock is not null then
      insert into public.positions(user_id,stock_id,quantity) values(new.id,v_stock,10000)
      on conflict(user_id,stock_id) do update set quantity=excluded.quantity;
    end if;
  end if;
  return new;
end;
$$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute procedure public.handle_new_user();

-- For creator signup that happened before this SQL was run, run this manually
-- after replacing creator@example.com with the creator's real account email:
-- update public.exchange_settings set setting_value='YOUR_REAL_EMAIL' where setting_key='creator_email';
-- update public.profiles set role='admin' where id=(select id from auth.users where lower(email)=lower('YOUR_REAL_EMAIL'));
-- insert into public.positions(user_id,stock_id,quantity)
-- select u.id,s.id,10000 from auth.users u cross join public.stocks s
-- where lower(u.email)=lower('YOUR_REAL_EMAIL') and s.symbol='ASTR'
-- on conflict(user_id,stock_id) do update set quantity=excluded.quantity;

create or replace function public.place_limit_order(
  p_stock_id uuid, p_side text, p_limit_price bigint, p_quantity bigint
) returns uuid language plpgsql security definer set search_path=public
as $$
declare
  v_uid uuid:=auth.uid(); v_order_id uuid; v_cash bigint; v_position bigint; v_cost bigint;
begin
  if v_uid is null then raise exception '로그인이 필요합니다.'; end if;
  if p_side not in ('buy','sell') then raise exception '잘못된 주문 유형입니다.'; end if;
  if p_limit_price<=0 or p_limit_price%10<>0 or p_quantity<=0 then
    raise exception '가격은 10원 단위, 수량은 1주 이상이어야 합니다.';
  end if;
  if p_limit_price>1000000000 or p_quantity>1000000 then raise exception '주문 한도를 초과했습니다.'; end if;
  if not exists(select 1 from public.stocks where id=p_stock_id) then raise exception '존재하지 않는 종목입니다.'; end if;
  v_cost:=p_limit_price*p_quantity;
  if p_side='buy' then
    select cash into v_cash from public.accounts where user_id=v_uid for update;
    if v_cash is null or v_cash<v_cost then raise exception '가상 현금이 부족합니다.'; end if;
    update public.accounts set cash=cash-v_cost where user_id=v_uid;
  else
    select quantity into v_position from public.positions where user_id=v_uid and stock_id=p_stock_id for update;
    if coalesce(v_position,0)<p_quantity then raise exception '매도 가능한 주식 수량이 부족합니다.'; end if;
    update public.positions set quantity=quantity-p_quantity where user_id=v_uid and stock_id=p_stock_id;
  end if;
  insert into public.orders(user_id,stock_id,side,limit_price,quantity)
  values(v_uid,p_stock_id,p_side,p_limit_price,p_quantity) returning id into v_order_id;
  return v_order_id;
end;
$$;
revoke all on function public.place_limit_order(uuid,text,bigint,bigint) from public;
grant execute on function public.place_limit_order(uuid,text,bigint,bigint) to authenticated;

-- Only users whose server-side profile role is admin can publish news.
create or replace function public.publish_news(p_title text,p_body text)
returns uuid language plpgsql security definer set search_path=public
as $$
declare v_uid uuid:=auth.uid(); v_id uuid;
begin
  if v_uid is null then raise exception '로그인이 필요합니다.'; end if;
  if not exists(select 1 from public.profiles where id=v_uid and role='admin') then
    raise exception '뉴스 발행 권한이 없습니다.';
  end if;
  if char_length(trim(p_title)) not between 1 and 120 or char_length(trim(p_body)) not between 1 and 5000 then
    raise exception '제목은 1~120자, 본문은 1~5000자로 입력하세요.';
  end if;
  insert into public.news(title,body,published,created_by)
  values(trim(p_title),trim(p_body),true,v_uid) returning id into v_id;
  return v_id;
end;
$$;
revoke all on function public.publish_news(text,text) from public;
grant execute on function public.publish_news(text,text) to authenticated;

-- No direct client insert/update/delete policies for orders, trades, cash, positions, or news.
-- Server-side RPCs are required for any mutations.
-- Enable Realtime in Supabase Dashboard for stocks, orders, trades, price_history and news as needed.
