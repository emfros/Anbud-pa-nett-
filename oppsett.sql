-- =====================================================================
--  Anbudsportal – databaseoppsett for Supabase
--  Lim inn hele filen i Supabase: SQL Editor → New query → Run.
--  Kan kjøres på nytt (den sletter og lager alt på nytt – OBS: også data).
-- =====================================================================
--
--  Prinsippene:
--  * To roller, begge må logge inn MED tofaktor:
--      admin     – Storebrand. Ser alle anbud og årsoversikten, tildeler oppdrag, gir roller.
--      takstmann – intern eller ekstern. Ser bare egne anbud. Anbefaler leverandør, men tildeler ikke.
--    Nye brukere får rollen «venter» og ser ingenting før en admin gir dem rolle.
--  * Leverandører har INGEN direkte tilgang til tabellene. De kan bare
--    kalle tre funksjoner (hent, send tilbud, still spørsmål), og må
--    oppgi en gyldig kode hver gang.
--  * Spørsmål og svar deles med alle leverandørene, men aldri hvem som spurte.
--  * Koden lagres aldri i klartekst – bare et "fingeravtrykk" (hash).
--  * Kalkylen din sendes aldri til leverandører.
--  * Summen regnes ut på serveren, ikke i nettleseren.
--  * Ingen kundenavn lagres. Bare skadenummer og adresse.
-- =====================================================================

drop view  if exists public.aarsoversikt;
drop table if exists public.sporsmal cascade;
drop function if exists public.sporsmal_vakt();
drop function if exists public.leverandor_sporsmal(text, text);
drop function if exists public.sporsmal_stengt(public.anbud);
drop table if exists public.kodeforsok cascade;
drop table if exists public.tilbud cascade;
drop table if exists public.invitasjon cascade;
drop table if exists public.anbud cascade;
drop trigger  if exists ny_bruker on auth.users;
drop function if exists public.ny_bruker() cascade;
drop function if exists public.kan_se_anbud(uuid) cascade;
drop function if exists public.er_admin() cascade;
drop function if exists public.er_innlogget() cascade;
drop function if exists public.min_rolle() cascade;
drop function if exists public.profil_vakt() cascade;
drop function if exists public.lag_invitasjon(uuid, text, text);
drop function if exists public.leverandor_hent(text);
drop function if exists public.leverandor_send(text, jsonb);
drop function if exists public.anbud_vakt();
drop function if exists public.tilbud_finn(text);
drop function if exists public.klient_ip();
drop function if exists public.orgnr_gyldig(text);

-- ---------------------------------------------------------------------
-- Hjelpefunksjoner
-- ---------------------------------------------------------------------

-- ---------------------------------------------------------------------
-- Brukere og roller. Tabellen slettes IKKE når filen kjøres på nytt,
-- så rollene du har gitt, blir stående.
-- ---------------------------------------------------------------------

create table if not exists public.profil (
  id        uuid primary key references auth.users(id) on delete cascade,
  epost     text not null,
  navn      text not null default '',
  firma     text not null default '',
  telefon   text not null default '',
  rolle     text not null default 'venter' check (rolle in ('admin','takstmann','venter','sperret')),
  type      text check (type in ('intern','ekstern')),   -- bare for takstmenn
  opprettet timestamptz not null default now()
);

-- Alle brukere som finnes fra før, får en profil (rolle «venter»)
insert into public.profil (id, epost)
  select id, coalesce(email, '') from auth.users on conflict (id) do nothing;

-- Nye brukere (lagt inn i Supabase) får automatisk en profil med rolle «venter»
create function public.ny_bruker() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profil (id, epost) values (new.id, coalesce(new.email, '')) on conflict (id) do nothing;
  return new;
end $$;
create trigger ny_bruker after insert on auth.users
  for each row execute function public.ny_bruker();

-- Rollen til den som er innlogget – bare hvis tofaktor er bekreftet i denne økten
create function public.min_rolle() returns text
language sql stable security definer set search_path = public as $$
  select rolle from public.profil
  where id = auth.uid() and coalesce(auth.jwt() ->> 'aal', '') = 'aal2'
$$;
create function public.er_admin() returns boolean
language sql stable as $$ select coalesce(public.min_rolle() = 'admin', false) $$;
create function public.er_innlogget() returns boolean
language sql stable as $$ select coalesce(public.min_rolle() in ('admin','takstmann'), false) $$;

-- Ingen kan endre e-post eller id, og det må alltid finnes minst én admin
create function public.profil_vakt() returns trigger
language plpgsql as $$
begin
  if new.id is distinct from old.id or new.epost is distinct from old.epost then
    raise exception 'E-post endres i Supabase, ikke her.';
  end if;
  if old.rolle = 'admin' and new.rolle <> 'admin'
     and (select count(*) from public.profil where rolle = 'admin') <= 1 then
    raise exception 'Det må alltid være minst én admin.';
  end if;
  if new.rolle <> 'takstmann' then new.type := null; end if;
  return new;
end $$;
drop trigger if exists profil_vakt on public.profil;
create trigger profil_vakt before update on public.profil
  for each row execute function public.profil_vakt();

alter table public.profil enable row level security;
drop policy if exists profil_les on public.profil;
drop policy if exists profil_endre on public.profil;
create policy profil_les on public.profil for select to authenticated
  using (id = auth.uid() or public.er_admin());
create policy profil_endre on public.profil for update to authenticated
  using (public.er_admin()) with check (public.er_admin());
revoke all on public.profil from anon;
revoke insert, delete on public.profil from authenticated;

-- Norsk organisasjonsnummer: 9 siffer med kontrollsiffer (modulus 11)
create function public.orgnr_gyldig(p text) returns boolean
language plpgsql immutable as $$
declare
  vekter int[] := array[3,2,7,6,5,4,3,2];
  s int := 0; k int; i int;
begin
  if p is null or p !~ '^[0-9]{9}$' then return false; end if;
  for i in 1..8 loop
    s := s + substr(p, i, 1)::int * vekter[i];
  end loop;
  k := 11 - (s % 11);
  if k = 11 then k := 0; end if;
  if k = 10 then return false; end if;
  return k = substr(p, 9, 1)::int;
end $$;

-- IP-adressen til den som spør (Supabase legger den i request.headers)
create function public.klient_ip() returns text
language sql stable as $$
  select coalesce(
    split_part(nullif(current_setting('request.headers', true), '')::json ->> 'x-forwarded-for', ',', 1),
    'ukjent')
$$;

-- ---------------------------------------------------------------------
-- Tabeller
-- ---------------------------------------------------------------------

create table public.anbud (
  id            uuid primary key default gen_random_uuid(),
  eier          uuid not null default auth.uid(),
  skadenr       text not null,
  adresse       text not null,
  skadetype     text not null,
  tittel        text not null default '',          -- Hva skal anskaffes
  beskrivelse   text not null default '',          -- Arbeidsomfang
  saerlige_forhold text not null default '',
  -- Takstmann og kontakt (vises for leverandørene)
  takst_navn    text not null default '',
  takst_firma   text not null default '',
  takst_epost   text not null default '',
  takst_tlf     text not null default '',
  -- Befaring og frister
  befaring      timestamptz,
  oppmote       text not null default '',
  frist_sporsmal date,
  frist         timestamptz not null,               -- Tilbudsfrist
  vedstaelse    date,                               -- Hvor lenge leverandøren må stå ved prisen
  onsket_ferdig text not null default '',
  tildelingsregel text not null default
    'Oppdraget tildeles laveste pris blant tilbud som oppfyller kravene. Byggetid og forbehold kan vektlegges.',
  status        text not null default 'utkast'
                check (status in ('utkast','utsendt','tildelt','avlyst')),
  -- [{id, navn, poster:[{id, fag, beskrivelse, mengde, enhet}]}]
  bygg          jsonb not null default '[]'::jsonb,
  -- Takstmannens enhetspriser per post: {"<post-id>": 1234.5}. Aldri synlig for leverandører.
  kalkyle       jsonb,
  kalkyle_sum   numeric(14,2),
  tildelt_invitasjon uuid,
  tildelt_begrunnelse text,
  -- Takstmannens anbefaling. Bare admin (Storebrand) kan tildele.
  anbefalt_invitasjon uuid,
  anbefalt_begrunnelse text,
  anbefalt_av   uuid,
  anbefalt_tid  timestamptz,
  opprettet     timestamptz not null default now(),
  utsendt       timestamptz
);

create table public.invitasjon (
  id          uuid primary key default gen_random_uuid(),
  anbud_id    uuid not null references public.anbud(id) on delete cascade,
  eier        uuid not null default auth.uid(),
  leverandor  text not null,
  epost       text,
  kode_hash   text not null unique,
  kode_slutt  text not null,           -- siste 4 tegn, så du kjenner igjen koden
  sendt       timestamptz,             -- når saksbehandler markerte e-posten som sendt (portalen sender aldri selv)
  sist_aapnet timestamptz,
  opprettet   timestamptz not null default now()
);

create table public.tilbud (
  invitasjon_id uuid primary key references public.invitasjon(id) on delete cascade,
  anbud_id      uuid not null references public.anbud(id) on delete cascade,
  eier          uuid not null,
  firmanavn     text not null,
  orgnr         text not null,
  kontakt       text not null,
  telefon       text,
  epost         text,
  priser        jsonb not null,        -- {"<post-id>": enhetspris eks. mva}
  forbehold     text not null default '',              -- Generelle forbehold
  forbehold_bygg jsonb not null default '{}'::jsonb,  -- {"<bygg-id>": "forbehold for dette bygget"}
  byggetid_uker numeric(6,1) not null,
  oppstart      date not null,
  timepris      numeric(10,2) not null,              -- For tilleggsarbeid, eks. mva
  bekreftet     boolean not null default false,
  sum_eks_mva   numeric(14,2) not null,
  levert        timestamptz not null default now(),
  antall_innsendinger int not null default 1
);

-- Logg over feilede kodeforsøk (for å stoppe gjetting)
create table public.kodeforsok (
  id  bigserial primary key,
  ip  text not null,
  tid timestamptz not null default now()
);
create index on public.kodeforsok (ip, tid);
create index on public.invitasjon (anbud_id);
create index on public.tilbud (anbud_id);

alter table public.anbud
  add constraint tildelt_fk foreign key (tildelt_invitasjon)
  references public.invitasjon(id) on delete set null deferrable initially deferred;
alter table public.anbud
  add constraint anbefalt_fk foreign key (anbefalt_invitasjon)
  references public.invitasjon(id) on delete set null deferrable initially deferred;

-- Kan den innloggede se dette anbudet? Admin ser alle, takstmann bare egne.
create function public.kan_se_anbud(p_anbud uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select public.er_admin()
      or (public.er_innlogget() and exists (select 1 from public.anbud where id = p_anbud and eier = auth.uid()))
$$;

-- ---------------------------------------------------------------------
-- Tilgangsregler (RLS). Uten en regel som slipper deg inn, ser du ingenting.
-- ---------------------------------------------------------------------

alter table public.anbud      enable row level security;
alter table public.invitasjon enable row level security;
alter table public.tilbud     enable row level security;
alter table public.kodeforsok enable row level security;   -- ingen regler = ingen tilgang

create policy anbud_tilgang on public.anbud for all to authenticated
  using (public.er_admin() or (public.er_innlogget() and eier = auth.uid()))
  with check (public.er_admin() or (public.er_innlogget() and eier = auth.uid()));

create policy invitasjon_tilgang on public.invitasjon for all to authenticated
  using (public.kan_se_anbud(anbud_id))
  with check (public.kan_se_anbud(anbud_id));

create policy tilbud_les on public.tilbud for select to authenticated
  using (public.kan_se_anbud(anbud_id));
create policy tilbud_slett on public.tilbud for delete to authenticated
  using (public.kan_se_anbud(anbud_id));

-- Leverandører (anon) får ingen direkte tabelltilgang i det hele tatt.
revoke all on public.anbud, public.invitasjon, public.tilbud, public.kodeforsok from anon;
revoke all on public.kodeforsok from authenticated;
revoke insert, update on public.tilbud from authenticated;

-- ---------------------------------------------------------------------
-- Vakt: når anbudet er sendt ut, kan ikke postene eller kalkylen endres.
-- Da kan ingen si at de priset noe annet enn det som står der.
-- ---------------------------------------------------------------------

create function public.anbud_vakt() returns trigger
language plpgsql as $$
declare laveste numeric; valgt numeric;
begin
  if tg_op = 'INSERT' then
    if new.status <> 'utkast' then
      raise exception 'Et nytt anbud må starte som utkast.';
    end if;
    new.anbefalt_invitasjon := null; new.anbefalt_begrunnelse := null; new.anbefalt_av := null; new.anbefalt_tid := null;
    new.tildelt_invitasjon := null; new.tildelt_begrunnelse := null;
    return new;
  end if;

  -- Hvem som anbefalte og når, settes bare her
  new.anbefalt_av := old.anbefalt_av; new.anbefalt_tid := old.anbefalt_tid;
  if (new.anbefalt_invitasjon, new.anbefalt_begrunnelse) is distinct from (old.anbefalt_invitasjon, old.anbefalt_begrunnelse) then
    if old.status <> 'utsendt' then
      raise exception 'Anbudet er avsluttet. Anbefalingen kan ikke endres.';
    end if;
    if new.anbefalt_invitasjon is null then
      new.anbefalt_begrunnelse := null; new.anbefalt_av := null; new.anbefalt_tid := null;
    else
      select sum_eks_mva into valgt from public.tilbud
        where invitasjon_id = new.anbefalt_invitasjon and anbud_id = new.id;
      if valgt is null then
        raise exception 'Anbefal et tilbud som er levert på dette anbudet.';
      end if;
      select min(sum_eks_mva) into laveste from public.tilbud where anbud_id = new.id;
      if valgt > laveste and coalesce(btrim(new.anbefalt_begrunnelse), '') = '' then
        raise exception 'Du anbefaler ikke laveste tilbud. Skriv en begrunnelse.';
      end if;
      new.anbefalt_av := auth.uid(); new.anbefalt_tid := now();
    end if;
  end if;

  if old.status <> 'utkast' and
     (new.bygg is distinct from old.bygg or new.kalkyle is distinct from old.kalkyle
      or new.kalkyle_sum is distinct from old.kalkyle_sum) then
    raise exception 'Poster og kalkyle er låst etter at anbudet er sendt ut.';
  end if;

  -- Vilkårene leverandørene har priset etter, låses også. Frister, befaring og kontaktinfo kan endres.
  if old.status <> 'utkast' and
     (new.skadenr, new.adresse, new.skadetype, new.tittel, new.beskrivelse, new.saerlige_forhold,
      new.vedstaelse, new.onsket_ferdig, new.tildelingsregel)
     is distinct from
     (old.skadenr, old.adresse, old.skadetype, old.tittel, old.beskrivelse, old.saerlige_forhold,
      old.vedstaelse, old.onsket_ferdig, old.tildelingsregel) then
    raise exception 'Beskrivelse og vilkår er låst etter at anbudet er sendt ut.';
  end if;

  if new.vedstaelse is not null and new.vedstaelse < (new.frist at time zone 'Europe/Oslo')::date then
    raise exception 'Vedståelsesfristen kan ikke være før tilbudsfristen.';
  end if;
  if new.frist_sporsmal is not null and new.frist_sporsmal > (new.frist at time zone 'Europe/Oslo')::date then
    raise exception 'Frist for spørsmål må være før tilbudsfristen.';
  end if;

  if old.status = 'utkast' and new.status = 'utsendt' then
    if new.kalkyle_sum is null or jsonb_array_length(new.bygg) = 0 then
      raise exception 'Legg inn poster og kalkyle før du sender ut.';
    end if;
    if btrim(new.tittel) = '' or btrim(new.beskrivelse) = ''
       or btrim(new.takst_navn) = '' or btrim(new.takst_epost) = '' or new.vedstaelse is null then
      raise exception 'Fyll inn hva som skal anskaffes, arbeidsomfang, takstmann, e-post og vedståelsesfrist før du sender ut.';
    end if;
    if new.frist <= now() then
      raise exception 'Tilbudsfristen må være frem i tid.';
    end if;
    new.utsendt := now();
  end if;

  if old.status <> 'tildelt' and (new.tildelt_invitasjon, new.tildelt_begrunnelse) is distinct from (old.tildelt_invitasjon, old.tildelt_begrunnelse)
     and new.status <> 'tildelt' then
    raise exception 'Tildeling skjer bare sammen med status «tildelt».';
  end if;
  if old.status = 'tildelt' and (new.tildelt_invitasjon, new.tildelt_begrunnelse) is distinct from (old.tildelt_invitasjon, old.tildelt_begrunnelse) then
    raise exception 'Saken er avsluttet og kan ikke åpnes igjen.';
  end if;

  if old.status in ('tildelt','avlyst') and new.status is distinct from old.status then
    raise exception 'Saken er avsluttet og kan ikke åpnes igjen.';
  end if;

  if new.status = 'tildelt' and old.status <> 'tildelt' then
    if not public.er_admin() then
      raise exception 'Bare Storebrand (admin) kan tildele oppdraget. Send en anbefaling i stedet.';
    end if;
    if old.status <> 'utsendt' then
      raise exception 'Bare utsendte anbud kan tildeles.';
    end if;
    select sum_eks_mva into valgt from public.tilbud
      where invitasjon_id = new.tildelt_invitasjon and anbud_id = new.id;
    if valgt is null then
      raise exception 'Velg et tilbud som er levert på dette anbudet.';
    end if;
    select min(sum_eks_mva) into laveste from public.tilbud where anbud_id = new.id;
    if valgt > laveste and coalesce(btrim(new.tildelt_begrunnelse), '') = '' then
      raise exception 'Du valgte ikke laveste tilbud. Skriv en begrunnelse.';
    end if;
  end if;
  return new;
end $$;

create trigger anbud_vakt before insert or update on public.anbud
  for each row execute function public.anbud_vakt();

-- ---------------------------------------------------------------------
-- Admin: lag en invitasjon. Koden vises én gang – bare hashen lagres.
-- Format: XXXX-XXXX-XXXX-XXXX (16 tegn, 64 bit tilfeldighet).
-- ---------------------------------------------------------------------

create function public.lag_invitasjon(p_anbud uuid, p_leverandor text, p_epost text default null)
returns jsonb
language plpgsql security invoker as $$
declare raa text; kode text; ny_id uuid;
begin
  if not public.er_innlogget() then
    raise exception 'Logg inn med tofaktor først.';
  end if;
  if coalesce(btrim(p_leverandor), '') = '' then
    raise exception 'Skriv inn navnet på leverandøren.';
  end if;
  raa  := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 16));
  kode := substr(raa,1,4) || '-' || substr(raa,5,4) || '-' || substr(raa,9,4) || '-' || substr(raa,13,4);
  insert into public.invitasjon (anbud_id, leverandor, epost, kode_hash, kode_slutt)
  values (p_anbud, btrim(p_leverandor), nullif(btrim(p_epost), ''),
          encode(sha256(convert_to(raa, 'UTF8')), 'hex'), substr(raa, 13, 4))
  returning id into ny_id;
  return jsonb_build_object('id', ny_id, 'kode', kode);
end $$;

-- ---------------------------------------------------------------------
-- Leverandør: slå opp en kode. Brukes av de to funksjonene under.
-- Stopper en IP etter 10 feil på 15 minutter.
-- ---------------------------------------------------------------------

create function public.tilbud_finn(p_kode text)
returns public.invitasjon
language plpgsql security definer set search_path = public as $$
declare inv public.invitasjon; ren text; v_ip text := public.klient_ip();
begin
  if (select count(*) from kodeforsok
      where kodeforsok.ip = v_ip and tid > now() - interval '15 minutes') >= 10 then
    raise exception 'For mange feil forsøk. Vent 15 minutter og prøv igjen.';
  end if;
  ren := upper(regexp_replace(coalesce(p_kode, ''), '[^A-Za-z0-9]', '', 'g'));
  select * into inv from invitasjon
    where kode_hash = encode(sha256(convert_to(ren, 'UTF8')), 'hex');
  if inv.id is null then
    insert into kodeforsok (ip) values (v_ip);
    return null;
  end if;
  return inv;
end $$;

-- ---------------------------------------------------------------------
-- Spørsmål og svar
--  * Leverandøren stiller spørsmål i portalen (frem til frist for spørsmål).
--  * Saksbehandler ser hvem som spurte, kan omformulere spørsmålet så det
--    ikke avslører avsender, og publiserer svaret til ALLE leverandørene.
--  * Saksbehandler kan også legge ut en avklaring uten at noen har spurt.
--  * Publiserte svar kan ikke endres eller slettes. Rettelser blir en ny avklaring.
-- ---------------------------------------------------------------------

create table public.sporsmal (
  id              uuid primary key default gen_random_uuid(),
  anbud_id        uuid not null references public.anbud(id) on delete cascade,
  eier            uuid not null default auth.uid(),
  invitasjon_id   uuid references public.invitasjon(id) on delete set null,  -- tom = avklaring fra saksbehandler
  sporsmal        text not null default '' check (char_length(sporsmal) <= 2000),  -- slik leverandøren skrev det
  publisert_tekst text check (char_length(publisert_tekst) <= 2000),               -- slik alle ser det
  svar            text check (char_length(svar) <= 5000),
  opprettet       timestamptz not null default now(),
  publisert       timestamptz
);
create index on public.sporsmal (anbud_id);

-- Hvorfor leverandørene ikke kan stille spørsmål akkurat nå (tom = de kan)
create function public.sporsmal_stengt(a public.anbud) returns text
language sql stable as $$
  select case
    when a.status <> 'utsendt' then 'Anbudet er stengt.'
    when now() >= a.frist then 'Fristen har gått ut.'
    when a.frist_sporsmal is not null and (now() at time zone 'Europe/Oslo')::date > a.frist_sporsmal
      then 'Fristen for spørsmål har gått ut.'
  end
$$;

create function public.sporsmal_vakt() returns trigger
language plpgsql as $$
declare st text;
begin
  if tg_op = 'DELETE' then
    -- Slettes hele anbudet, følger spørsmålene med. Ellers kan publiserte svar ikke slettes.
    if old.publisert is not null and exists (select 1 from public.anbud where id = old.anbud_id) then
      raise exception 'Publiserte svar kan ikke slettes. Legg ut en avklaring i stedet.';
    end if;
    return old;
  end if;

  if tg_op = 'INSERT' then
    select status into st from public.anbud where id = new.anbud_id;
    if st is distinct from 'utsendt' then
      raise exception 'Spørsmål og svar er stengt for dette anbudet.';
    end if;
    if new.invitasjon_id is null then           -- avklaring fra saksbehandler
      if coalesce(btrim(new.svar), '') = '' then raise exception 'Skriv avklaringen.'; end if;
      new.sporsmal := ''; new.svar := btrim(new.svar);
      new.publisert_tekst := nullif(btrim(new.publisert_tekst), '');
      new.publisert := now();
    else                                         -- spørsmål fra leverandør
      new.svar := null; new.publisert_tekst := null; new.publisert := null;
    end if;
    new.opprettet := now();
    return new;
  end if;

  -- UPDATE
  if old.publisert is not null then
    if (new.anbud_id, new.sporsmal, new.publisert_tekst, new.svar, new.publisert, new.opprettet)
       is distinct from (old.anbud_id, old.sporsmal, old.publisert_tekst, old.svar, old.publisert, old.opprettet) then
      raise exception 'Publiserte svar kan ikke endres. Legg ut en avklaring i stedet.';
    end if;
    return new;
  end if;
  if (new.anbud_id, new.sporsmal, new.opprettet) is distinct from (old.anbud_id, old.sporsmal, old.opprettet) then
    raise exception 'Spørsmålet slik leverandøren skrev det kan ikke endres.';
  end if;
  if new.publisert is not null then              -- publiser nå
    select status into st from public.anbud where id = new.anbud_id;
    if st is distinct from 'utsendt' then
      raise exception 'Anbudet er avsluttet. Svar kan ikke publiseres.';
    end if;
    if coalesce(btrim(new.svar), '') = '' then raise exception 'Skriv et svar før du publiserer.'; end if;
    new.svar := btrim(new.svar);
    new.publisert_tekst := coalesce(nullif(btrim(new.publisert_tekst), ''), old.sporsmal);
    new.publisert := now();
  end if;
  return new;
end $$;

create trigger sporsmal_vakt before insert or update or delete on public.sporsmal
  for each row execute function public.sporsmal_vakt();

alter table public.sporsmal enable row level security;
create policy sporsmal_les on public.sporsmal for select to authenticated
  using (public.kan_se_anbud(anbud_id));
create policy sporsmal_endre on public.sporsmal for update to authenticated
  using (public.kan_se_anbud(anbud_id)) with check (public.kan_se_anbud(anbud_id));
create policy sporsmal_slett on public.sporsmal for delete to authenticated
  using (public.kan_se_anbud(anbud_id));
-- Saksbehandler kan bare legge inn avklaringer selv. Spørsmål kommer fra leverandørene.
create policy sporsmal_avklaring on public.sporsmal for insert to authenticated
  with check (public.kan_se_anbud(anbud_id) and invitasjon_id is null);
revoke all on public.sporsmal from anon;

create function public.leverandor_sporsmal(p_kode text, p_tekst text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare inv invitasjon; a anbud; grunn text; tekst text := btrim(coalesce(p_tekst, '')); ny sporsmal;
begin
  inv := tilbud_finn(p_kode);
  if inv.id is null then
    return jsonb_build_object('ok', false, 'feil', 'Koden er ikke gyldig.');
  end if;
  select * into a from anbud where id = inv.anbud_id;
  grunn := sporsmal_stengt(a);
  if grunn is not null then
    return jsonb_build_object('ok', false, 'feil', grunn);
  end if;
  if char_length(tekst) < 5 then
    return jsonb_build_object('ok', false, 'feil', 'Skriv spørsmålet.');
  end if;
  if char_length(tekst) > 2000 then
    return jsonb_build_object('ok', false, 'feil', 'Spørsmålet er for langt (maks 2000 tegn).');
  end if;
  if (select count(*) from sporsmal where invitasjon_id = inv.id) >= 20 then
    return jsonb_build_object('ok', false, 'feil', 'Dere har nådd grensen på 20 spørsmål. Kontakt takstmannen direkte.');
  end if;
  insert into sporsmal (anbud_id, eier, invitasjon_id, sporsmal)
  values (a.id, a.eier, inv.id, tekst) returning * into ny;
  return jsonb_build_object('ok', true, 'opprettet', ny.opprettet);
end $$;

create function public.leverandor_hent(p_kode text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare inv invitasjon; a anbud; t tilbud; forrige timestamptz;
begin
  inv := tilbud_finn(p_kode);
  if inv.id is null then
    return jsonb_build_object('ok', false, 'feil', 'Koden er ikke gyldig. Sjekk at du har skrevet den riktig.');
  end if;
  select * into a from anbud where id = inv.anbud_id;
  if a.status = 'utkast' then
    return jsonb_build_object('ok', false, 'feil', 'Anbudet er ikke åpnet ennå.');
  end if;
  if a.status = 'avlyst' then
    return jsonb_build_object('ok', false, 'feil', 'Anbudet er avlyst.');
  end if;
  forrige := inv.sist_aapnet;
  update invitasjon set sist_aapnet = now() where id = inv.id;
  select * into t from tilbud where invitasjon_id = inv.id;
  return jsonb_build_object(
    'ok', true,
    'leverandor', inv.leverandor,
    'forrige_besok', forrige,
    'sporsmal_stengt', sporsmal_stengt(a),
    -- Publiserte spørsmål og svar: aldri hvem som spurte
    'qa', (select coalesce(jsonb_agg(jsonb_build_object(
              'sporsmal', s.publisert_tekst, 'svar', s.svar, 'publisert', s.publisert,
              'avklaring', s.sporsmal = '') order by s.publisert), '[]'::jsonb)
           from sporsmal s where s.anbud_id = a.id and s.publisert is not null),
    -- Egne spørsmål som venter på svar
    'mine', (select coalesce(jsonb_agg(jsonb_build_object('sporsmal', s.sporsmal, 'opprettet', s.opprettet)
              order by s.opprettet), '[]'::jsonb)
           from sporsmal s where s.invitasjon_id = inv.id and s.publisert is null),
    'aapen', a.status = 'utsendt' and now() < a.frist,
    'anbud', jsonb_build_object(              -- NB: ingen kalkyle her
      'skadenr', a.skadenr, 'adresse', a.adresse, 'skadetype', a.skadetype,
      'tittel', a.tittel, 'beskrivelse', a.beskrivelse, 'saerlige_forhold', a.saerlige_forhold,
      'takst_navn', a.takst_navn, 'takst_firma', a.takst_firma, 'takst_epost', a.takst_epost, 'takst_tlf', a.takst_tlf,
      'befaring', a.befaring, 'oppmote', a.oppmote, 'frist_sporsmal', a.frist_sporsmal,
      'frist', a.frist, 'vedstaelse', a.vedstaelse, 'onsket_ferdig', a.onsket_ferdig,
      'tildelingsregel', a.tildelingsregel, 'bygg', a.bygg),
    'tilbud', case when t.invitasjon_id is null then null else jsonb_build_object(
      'firmanavn', t.firmanavn, 'orgnr', t.orgnr, 'kontakt', t.kontakt,
      'telefon', t.telefon, 'epost', t.epost, 'priser', t.priser,
      'forbehold', t.forbehold, 'forbehold_bygg', t.forbehold_bygg,
      'byggetid_uker', t.byggetid_uker, 'oppstart', t.oppstart, 'timepris', t.timepris,
      'bekreftet', t.bekreftet, 'sum_eks_mva', t.sum_eks_mva, 'levert', t.levert) end
  );
end $$;

create function public.leverandor_send(p_kode text, p_tilbud jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  inv invitasjon; a anbud; b jsonb; p jsonb; pris numeric; mengde numeric;
  total numeric := 0; v_priser jsonb := '{}'::jsonb; mangler int := 0;
  v_orgnr text := regexp_replace(coalesce(p_tilbud->>'orgnr', ''), '\s', '', 'g');
  v_levert timestamptz;
  v_byggetid numeric; v_timepris numeric; v_oppstart date;
  v_fb jsonb := '{}'::jsonb; fb_tekst text;
begin
  inv := tilbud_finn(p_kode);
  if inv.id is null then
    return jsonb_build_object('ok', false, 'feil', 'Koden er ikke gyldig.');
  end if;
  select * into a from anbud where id = inv.anbud_id for share;
  if a.status <> 'utsendt' or now() >= a.frist then
    return jsonb_build_object('ok', false, 'feil', 'Fristen har gått ut. Tilbudet ble ikke sendt.');
  end if;
  if coalesce(btrim(p_tilbud->>'firmanavn'), '') = '' or coalesce(btrim(p_tilbud->>'kontakt'), '') = '' then
    return jsonb_build_object('ok', false, 'feil', 'Fyll inn firmanavn og kontaktperson.');
  end if;
  if not orgnr_gyldig(v_orgnr) then
    return jsonb_build_object('ok', false, 'feil', 'Organisasjonsnummeret er ikke gyldig.');
  end if;

  -- Gjennomføring: byggetid, oppstart og timepris er påkrevd
  begin v_byggetid := (p_tilbud->>'byggetid_uker')::numeric; exception when others then v_byggetid := null; end;
  begin v_timepris := (p_tilbud->>'timepris')::numeric;      exception when others then v_timepris := null; end;
  begin v_oppstart := (p_tilbud->>'oppstart')::date;          exception when others then v_oppstart := null; end;
  if v_byggetid is null or v_byggetid <= 0 or v_byggetid > 520 then
    return jsonb_build_object('ok', false, 'feil', 'Oppgi byggetid i uker.');
  end if;
  if v_oppstart is null then
    return jsonb_build_object('ok', false, 'feil', 'Oppgi når dere kan starte.');
  end if;
  if v_timepris is null or v_timepris < 0 then
    return jsonb_build_object('ok', false, 'feil', 'Oppgi timepris for tilleggsarbeid.');
  end if;
  if coalesce(p_tilbud->'bekreftet' = 'true'::jsonb, false) is not true then
    return jsonb_build_object('ok', false, 'feil', 'Bekreft at tilbudet følger kravene i anbudet.');
  end if;

  -- Forbehold per bygg: bare bygg som finnes i anbudet, og bare tekst som ikke er tom
  for b in select * from jsonb_array_elements(a.bygg) loop
    fb_tekst := btrim(coalesce(p_tilbud->'forbehold_bygg'->>(b->>'id'), ''));
    if fb_tekst <> '' then v_fb := v_fb || jsonb_build_object(b->>'id', fb_tekst); end if;
  end loop;

  -- Regn ut summen her, ut fra mengdene i anbudet. Tallet fra nettleseren brukes ikke.
  for b in select * from jsonb_array_elements(a.bygg) loop
    for p in select * from jsonb_array_elements(b->'poster') loop
      begin
        pris := (p_tilbud->'priser'->>(p->>'id'))::numeric;
      exception when others then pris := null;
      end;
      if pris is null or pris < 0 then
        mangler := mangler + 1;
      else
        mengde := coalesce((p->>'mengde')::numeric, 0);
        total  := total + round(pris * mengde, 2);
        v_priser := v_priser || jsonb_build_object(p->>'id', pris);
      end if;
    end loop;
  end loop;
  if mangler > 0 then
    return jsonb_build_object('ok', false, 'feil', mangler || ' post(er) mangler pris.');
  end if;

  insert into tilbud (invitasjon_id, anbud_id, eier, firmanavn, orgnr, kontakt, telefon, epost,
                      priser, forbehold, forbehold_bygg, byggetid_uker, oppstart, timepris, bekreftet, sum_eks_mva)
  values (inv.id, a.id, a.eier, btrim(p_tilbud->>'firmanavn'), v_orgnr, btrim(p_tilbud->>'kontakt'),
          nullif(btrim(p_tilbud->>'telefon'), ''), nullif(btrim(p_tilbud->>'epost'), ''),
          v_priser, btrim(coalesce(p_tilbud->>'forbehold', '')), v_fb, v_byggetid, v_oppstart, v_timepris, true, total)
  on conflict (invitasjon_id) do update set
    firmanavn = excluded.firmanavn, orgnr = excluded.orgnr, kontakt = excluded.kontakt,
    telefon = excluded.telefon, epost = excluded.epost, priser = excluded.priser,
    forbehold = excluded.forbehold, forbehold_bygg = excluded.forbehold_bygg,
    byggetid_uker = excluded.byggetid_uker, oppstart = excluded.oppstart, timepris = excluded.timepris,
    bekreftet = excluded.bekreftet, sum_eks_mva = excluded.sum_eks_mva,
    levert = now(), antall_innsendinger = tilbud.antall_innsendinger + 1
  returning tilbud.levert into v_levert;

  return jsonb_build_object('ok', true, 'sum_eks_mva', total, 'levert', v_levert,
    'kvittering', upper(substr(md5(inv.id::text || v_levert::text), 1, 8)));
end $$;

-- Hvem kan kalle hva
revoke execute on function public.tilbud_finn(text) from public, anon, authenticated;
revoke execute on function public.lag_invitasjon(uuid, text, text) from public, anon;
revoke execute on function public.leverandor_hent(text) from public;
revoke execute on function public.leverandor_send(text, jsonb) from public;
grant  execute on function public.lag_invitasjon(uuid, text, text) to authenticated;
grant  execute on function public.leverandor_hent(text) to anon, authenticated;
grant  execute on function public.leverandor_send(text, jsonb) to anon, authenticated;
revoke execute on function public.leverandor_sporsmal(text, text) from public;
grant  execute on function public.leverandor_sporsmal(text, text) to anon, authenticated;
revoke execute on function public.sporsmal_stengt(public.anbud) from public, anon;

-- ---------------------------------------------------------------------
-- Årsoversikt: én rad per anbud, klar for besparelse per år.
-- Følger de samme tilgangsreglene (security_invoker).
-- ---------------------------------------------------------------------

create view public.aarsoversikt with (security_invoker = true) as
select
  a.id, a.skadenr, a.skadetype, a.status,
  extract(year from coalesce(a.utsendt, a.opprettet))::int as aar,
  a.kalkyle_sum,
  count(t.invitasjon_id)                                    as antall_tilbud,
  min(t.sum_eks_mva)                                        as laveste,
  round(avg(t.sum_eks_mva), 2)                              as snitt,
  max(t.sum_eks_mva) filter (where t.invitasjon_id = a.tildelt_invitasjon) as tildelt_sum,
  a.kalkyle_sum - max(t.sum_eks_mva) filter (where t.invitasjon_id = a.tildelt_invitasjon)
                                                            as besparelse_mot_kalkyle,
  round(avg(t.sum_eks_mva), 2) - max(t.sum_eks_mva) filter (where t.invitasjon_id = a.tildelt_invitasjon)
                                                            as besparelse_mot_snitt
from public.anbud a
left join public.tilbud t on t.anbud_id = a.id
where public.er_admin()          -- bare Storebrand ser besparelser
group by a.id;

revoke all on public.aarsoversikt from anon;
