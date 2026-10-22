# Anbudsportal – slik setter du den opp

Tre filer:

- **index.html** – hele nettsiden. Står nøklene øverst tomme, kjører den som demo.
- **oppsett.sql** – databasen med alle tilgangsregler.
- **LES-MEG.md** – denne filen.

Regn med 1–2 timer første gang. Alt er gratis bortsett fra domenet (ca. 100–200 kr i året).

> Bruk bare oppdiktede data til dette er godkjent av IT. Ingen ekte skadesaker, adresser eller leverandørpriser.

---

## 1. Lag databasen (Supabase)

1. Lag en konto på **supabase.com** og trykk **New project**.
2. Velg region i EU, for eksempel **Stockholm** eller **Frankfurt**. Da ligger dataene i EU.
3. Gi databasen et sterkt passord og lagre det i passordbehandleren din.
4. Når prosjektet er klart: gå til **SQL Editor** → **New query**. Lim inn hele `oppsett.sql` og trykk **Run**. Du skal få «Success».

## 2. Lag brukeren din, og steng for andre

1. Gå til **Authentication** → **Sign In / Providers** (kan hete «Settings»). Slå **av** «Allow new users to sign up». Da kan ingen andre lage konto.
2. Gå til **Authentication** → **Users** → **Add user**. Skriv inn e-posten din og et langt passord. Huk av for «Auto confirm».
3. Tofaktor (TOTP) er på som standard i Supabase. Første gang du logger inn, viser siden en QR-kode du skanner med Microsoft Authenticator eller Google Authenticator.

## 3. Koble nettsiden til databasen

1. Gå til **Project Settings** → **API** (eller «API Keys»).
2. Kopier **Project URL** og nøkkelen som heter **anon** eller **publishable**.
3. Åpne `index.html` i en teksteditor. Lim dem inn helt øverst i skriptet:

```js
const SUPABASE_URL = 'https://abcdefgh.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOi...';
```

Den nøkkelen er laget for å ligge åpent i nettsider. Sikkerheten ligger i tilgangsreglene i databasen.
**Bruk aldri nøkkelen som heter `service_role` eller `secret`.** Den går forbi alle reglene.

## 4. Legg nettsiden ut (Netlify)

1. Lag en mappe som bare inneholder `index.html`.
2. Gå til **app.netlify.com/drop** og dra mappen inn i nettleseren.
3. Du får en adresse som `noe-tilfeldig.netlify.app`. Siden virker allerede der, med HTTPS (kryptert tilkobling).

Når du endrer `index.html` senere: dra mappen inn på nytt under **Deploys** i Netlify.

## 5. Koble på ditt eget domene

1. Kjøp domenet, for eksempel hos **Domeneshop**.
2. I Netlify: **Domain management** → **Add a domain** → skriv inn domenet.
3. Netlify viser hvilke DNS-oppføringer du skal legge inn. DNS er «telefonkatalogen» som forteller nettet hvor domenet ditt bor. Hos Domeneshop legger du dem inn under **DNS**. Vanligvis:
   - `www` → **CNAME** → `noe-tilfeldig.netlify.app`
   - selve domenet → **A** → IP-adressen Netlify oppgir
4. Vent fra noen minutter til noen timer. Netlify lager HTTPS-sertifikatet selv.
5. Tilbake i Supabase: **Authentication** → **URL Configuration**. Sett **Site URL** til `https://ditt-domene.no`.

## 6. Test hele løpet

1. Gå til domenet og trykk **Logg inn**. Sett opp tofaktor.
2. Lag et anbud med oppdiktede data og send det ut.
3. Inviter deg selv som leverandør. Kopier koden.
4. Åpne siden i et **privat vindu** og skriv inn koden. Lever et tilbud.
5. Gå tilbake som admin. Tilbudet skal ligge der. Tildel det og sjekk **Årsoversikt**.

Hvis noe feiler: åpne nettleserens utviklerverktøy (F12 → Console) og send meg feilmeldingen.

---

## Hva som beskytter dataene

| Risiko | Hva som stopper det |
|---|---|
| Noen gjetter en kode | Koden har 16 tegn (ca. 18 milliarder milliarder muligheter). Etter 10 feil på 15 minutter stenges IP-adressen. |
| Koden lekker fra databasen | Koden lagres bare som et fingeravtrykk (hash). Du ser den én gang når du lager den. |
| Leverandør ser andres priser | Leverandører har ingen tilgang til tabellene. De får bare sitt eget anbud og sitt eget tilbud. |
| Leverandør ser kalkylen din | Kalkylen sendes aldri ut. Testet. |
| Noen jukser med summen i nettleseren | Summen regnes ut på serveren, ut fra mengdene i anbudet. |
| Poster endres etter at tilbud er gitt | Poster og kalkyle låses når anbudet sendes ut. |
| Noen stjeler passordet ditt | Alt krever tofaktor. Uten det ser du ingenting, selv med riktig passord. |
| Tilbud etter fristen | Databasen avviser det, uansett hva nettsiden sier. |
| Tildeling uten grunn | Velger du ikke laveste tilbud, må du skrive begrunnelse. Det lagres. |

## Hva som er testet – og hva som ikke er det

- **Databasen:** kjørt i ekte Postgres med 42 tester av tilgangsreglene. Alle bestått.
- **Nettsiden:** klikket gjennom hele løpet i Chrome, på mobil- og PC-bredde, i demo-modus.
- **Ikke testet:** koblingen mot et ekte Supabase-prosjekt (innlogging og tofaktor). Koden følger Supabase sin dokumentasjon, men første oppkobling kan trenge en liten justering.

## Kjente begrensninger i demoen

- E-post til leverandørene sendes ikke automatisk. Du kopierer ferdig tekst og sender selv.
- Ingen vedlegg (tegninger, bilder). Kan legges til med Supabase Storage.
- Kontraktsvilkår og konkurransegrunnlag fra det gamle skjemaet ditt er ikke med ennå.
- Gratisversjonen av Supabase pauser prosjektet etter en uke uten bruk. Du starter det igjen med ett klikk.
