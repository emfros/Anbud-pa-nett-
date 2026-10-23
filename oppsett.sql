-- =====================================================================
--  Anbudsportal – databaseoppsett for Supabase
--  Lim inn hele filen i Supabase: SQL Editor → New query → Run.
--  Kan kjøres på nytt (den sletter og lager alt på nytt – OBS: også data).
-- =====================================================================
--
--  Prinsippene:
--  * Bare du (innlogget MED tofaktor) kan lese og endre anbud.
--  * Leverandører har INGEN direkte tilgang til tabellene. De kan bare
--    kalle to funksjoner, og må oppgi en gyldig kode hver gang.
--  * Koden lagres aldri i klartekst – bare et "fingeravtrykk" (hash).
--  * Kalkylen din sendes aldri til leverandører.
--  * Summen regnes ut på serveren, ikke i nettleseren.
--  * Ingen kundenavn lagres. Bare skadenummer og adresse.
-- =====================================================================

drop view  if exists public.aarsoversikt;
drop table if exists public.kodeforsok cascade;
drop table if exists public.tilbud cascade;
drop table if exists public.invitasjon cascade;
drop table if exists public.anbud cascade;
drop function if exists public.er_admin();
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

-- Innlogget, og har bekreftet tofaktor i denne økten?
create function public.er_admin() returns boolean
language sql stable as $$
  select auth.uid() is not null
     and coalesce(auth.jwt() ->> 'aal', '') = 'aal2'
$$;

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

-- ---------------------------------------------------------------------
-- Tilgangsregler (RLS). Uten en regel som slipper deg inn, ser du ingenting.
-- ---------------------------------------------------------------------

alter table public.anbud      enable row level security;
alter table public.invitasjon enable row level security;
alter table public.tilbud     enable row level security;
alter table public.kodeforsok enable row level security;   -- ingen regler = ingen tilgang

create policy anbud_eier on public.anbud for all to authenticated
  using (public.er_admin() and eier = auth.uid())
  with check (public.er_admin() and eier = auth.uid());

create policy invitasjon_eier on public.invitasjon for all to authenticated
  using (public.er_admin() and eier = auth.uid())
  with check (public.er_admin() and eier = auth.uid()
              and exists (select 1 from public.anbud a
                          where a.id = anbud_id and a.eier = auth.uid()));

-- Tilbud kan du lese og slette, men ikke endre (det er leverandørens tall).
create policy tilbud_les on public.tilbud for select to authenticated
  using (public.er_admin() and eier = auth.uid());
create policy tilbud_slett on public.tilbud for delete to authenticated
  using (public.er_admin() and eier = auth.uid());

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
    return new;
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

  if old.status in ('tildelt','avlyst') and new.status is distinct from old.status then
    raise exception 'Saken er avsluttet og kan ikke åpnes igjen.';
  end if;

  if new.status = 'tildelt' and old.status <> 'tildelt' then
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
  if not public.er_admin() then
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

create function public.leverandor_hent(p_kode text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare inv invitasjon; a anbud; t tilbud;
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
  update invitasjon set sist_aapnet = now() where id = inv.id;
  select * into t from tilbud where invitasjon_id = inv.id;
  return jsonb_build_object(
    'ok', true,
    'leverandor', inv.leverandor,
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
group by a.id;

revoke all on public.aarsoversikt from anon;
