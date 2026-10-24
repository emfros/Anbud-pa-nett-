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

## 2. Lag brukeren din, gjør deg til admin, og steng for andre

1. Gå til **Authentication** → **Sign In / Providers** (kan hete «Settings»). Slå **av** «Allow new users to sign up». Da kan ingen andre lage konto.
2. Gå til **Authentication** → **Users** → **Add user**. Skriv inn e-posten din og et langt passord. Huk av for «Auto confirm».
3. Gå til **SQL Editor** og kjør denne linjen, med din e-post. Den gjør deg til admin. Det trengs bare første gang:

```sql
update public.profil set rolle = 'admin' where epost = 'din@epost.no';
```

4. Tofaktor (TOTP) er på som standard i Supabase. Første gang du logger inn, viser siden en QR-kode du skanner med Microsoft Authenticator eller Google Authenticator.

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

1. Gå til `https://ditt-domene.no/#intern` og logg inn. Sett opp tofaktor. Lagre adressen som bokmerke. Forsiden uten `#intern` er for leverandørene og har bare kodefeltet.
2. Lag et anbud med oppdiktede data og send det ut.
3. Inviter deg selv som leverandør. Kopier koden.
4. Åpne siden i et **privat vindu** og skriv inn koden. Lever et tilbud.
5. Gå tilbake som admin. Tilbudet skal ligge der. Tildel det og sjekk **Årsoversikt**.
6. Lag en testbruker for en takstmann (se «Roller og brukere»), logg inn som den, og sjekk at du bare ser det den har laget.

Hvis noe feiler: åpne nettleserens utviklerverktøy (F12 → Console) og send meg feilmeldingen.

---

## To innganger

- **Forsiden** (`ditt-domene.no`) er for leverandørene. Der er det bare et felt for koden. Lenken i e-posten går hit, med koden ferdig utfylt.
- **Intern innlogging** (`ditt-domene.no/#intern`) er for Storebrand og takstmenn. Alle logger inn med samme skjema. Systemet vet hvem du er og hva du får se.

Å skjule innloggingen er ikke det som gir sikkerhet. Sikkerheten ligger i databasen. Men forsiden blir ryddigere for leverandørene.

Senere vil IT trolig at Storebrand-ansatte logger inn med jobbkontoen (Microsoft). Da legges det til en knapp på samme innloggingsside. Eksterne takstmenn bruker fortsatt e-post og passord.

## Roller og brukere

| | Admin (Storebrand) | Takstmann (intern eller ekstern) |
|---|---|---|
| Lage anbud, invitere, svare på spørsmål | Ja | Ja |
| Se anbud | Alle | Bare sine egne |
| Årsoversikt og besparelser | Ja | Nei |
| Tildele oppdraget | Ja | Nei – anbefaler, og Storebrand tildeler |
| Gi roller og tilgang | Ja | Nei |

**Slik legger du til en ny bruker:**

1. I Supabase: **Authentication** → **Users** → **Add user**. Skriv e-post og et midlertidig passord, og huk av for «Auto confirm». Gi brukeren passordet på en trygg måte.
2. I portalen: gå til **Brukere**. Den nye brukeren står der som «Venter på tilgang» og ser ingenting ennå.
3. Velg rolle. For takstmenn velger du også intern eller ekstern. Trykk **Lagre**.

**Slik stenger du tilgangen** når en takstmann slutter: sett rollen til «Sperret». Da ser de ingenting, selv om de logger inn. Det må alltid være minst én admin.

**Anbefaling og tildeling:** Takstmannen velger tilbudet de mener er best, og trykker «Send anbefaling til Storebrand». Anbefaler de ikke laveste tilbud, må de skrive begrunnelse. I listen din står anbudet som «Venter på tildeling». Du ser anbefalingen og begrunnelsen, og tildeler selv.

**Før eksterne takstmenn får tilgang:** De får se Storebrand-data. Snakk med IT om en avtale for hvordan de behandler dataene (databehandleravtale), og om hvem som stenger tilgangen når samarbeidet slutter.

## Slik fungerer anbudet

**Den som lager anbudet** (admin eller takstmann) fyller ut seks steg:

1. **Saken** – skadenummer, skadetype, adresse og hva som skal anskaffes.
2. **Takstmann og kontakt** – hvem leverandørene sender spørsmål til.
3. **Befaring og frister** – befaring, frist for spørsmål, tilbudsfrist og vedståelsesfrist (hvor lenge leverandøren må stå ved prisen).
4. **Beskrivelse av arbeidet** – arbeidsomfang og særlige forhold. Faste krav står alltid med.
5. **Bygninger og poster** – mengder per post og din kalkyle.
6. **Tildeling** – hvordan leverandør velges.

**Leverandøren** ser alt dette, og fyller ut firma, byggetid, tidligste oppstart, timepris for tilleggsarbeid, pris per post og forbehold per bygg. Til slutt krysser de av for at tilbudet følger kravene.

Når du sammenligner, ser du byggetid, oppstart, timepris og forbehold ved siden av prisen.

## Slik inviterer du leverandører

Portalen sender aldri e-post selv. Du sender fra din egen e-post, i tre steg:

1. **Skriv inn firma og e-post**, og trykk «Se e-posten».
2. **Se over e-posten.** Du ser hvem den er fra (deg), hvem den går til, emnet og teksten. Du kan endre alt. `[KODE]` byttes ut med leverandørens personlige kode.
3. **Trykk «Lag kode og åpne e-post».** E-posten åpnes ferdig utfylt i e-postprogrammet ditt, for eksempel Outlook. Du ser over og sender selv. Trykk så «Ja, marker som sendt» i portalen.

Send én e-post per leverandør. Koden er personlig, og leverandørene skal ikke se hvem de konkurrerer med.

E-posten har også en lenke der koden er fylt inn, så leverandøren slipper å skrive den.

Under «Invitasjoner» ser du status for hver leverandør: ikke sendt, sendt, åpnet eller levert.

**Hvorfor sender ikke portalen selv?** En e-post med kode fra et ukjent domene som sier at den er fra Storebrand, ser ut som svindel og havner ofte i søppelposten. Skal portalen sende selv, bør det skje fra en Storebrand-adresse, og det krever IT.

## Spørsmål og svar

- **Leverandøren** stiller spørsmål i portalen, frem til frist for spørsmål (eller tilbudsfristen hvis du ikke har satt en egen frist). Maks 20 spørsmål per leverandør.
- **Du** ser hvem som spurte. Før du publiserer, kan du skrive om spørsmålet så det ikke avslører hvem som spør.
- **Svaret publiseres til alle** leverandørene på samme anbud. De ser aldri hvem som spurte.
- Du kan også legge ut en **avklaring** til alle, uten at noen har spurt.
- **Publiserte svar kan ikke endres eller slettes.** Har du skrevet feil, legger du ut en avklaring.
- Leverandøren får beskjed om nye svar siden sist. Kommer det svar etter at de har levert, blir de bedt om å sjekke om tilbudet må endres.
- Det sendes ingen e-post. I listen over anbud ser du hvor mange spørsmål som venter på svar.

## Har du allerede satt opp databasen?

Kjør hele `oppsett.sql` på nytt i Supabase. Den lager tabellene på nytt med de nye feltene. **Alle anbud, tilbud og spørsmål blir slettet.** Det går fint så lenge du bare har testdata.

Brukerne og rollene deres blir stående. Det er bare første gang du må gjøre deg selv til admin med SQL-linjen i steg 2.

## Hva som beskytter dataene

| Risiko | Hva som stopper det |
|---|---|
| Noen gjetter en kode | Koden har 16 tegn (ca. 18 milliarder milliarder muligheter). Etter 10 feil på 15 minutter stenges IP-adressen. |
| Koden lekker fra databasen | Koden lagres bare som et fingeravtrykk (hash). Du ser den én gang når du lager den. |
| Leverandør ser andres priser | Leverandører har ingen tilgang til tabellene. De får bare sitt eget anbud og sitt eget tilbud. |
| Leverandør ser kalkylen din | Kalkylen sendes aldri ut. Testet. |
| Noen jukser med summen i nettleseren | Summen regnes ut på serveren, ut fra mengdene i anbudet. |
| Anbudet endres etter at tilbud er gitt | Beskrivelse, vilkår, poster og kalkyle låses når anbudet sendes ut. Bare frister og befaring kan endres etterpå. |
| Takstmann ser andres anbud | Databasen viser takstmenn bare anbud de har laget selv, med tilbud og spørsmål som hører til. |
| Takstmann tildeler oppdraget selv | Databasen avviser det. Bare admin kan tildele. Takstmannen kan bare anbefale. |
| Takstmann ser besparelser | Årsoversikten er tom for alle andre enn admin. |
| Noen gir seg selv admin | Bare admin kan endre roller. Nye brukere starter som «Venter på tilgang». Det må alltid finnes minst én admin. |
| Tidligere takstmann logger inn | Sett rollen til «Sperret». Da ser de ingenting. |
| E-post går til feil leverandør | Ingenting sendes automatisk. Du ser hver e-post før den sendes, og sender den selv. |
| Leverandør får vite hvem som spurte | Leverandørene ser bare den publiserte teksten, aldri hvem som spurte. Du kan skrive om spørsmålet før du publiserer. |
| Svar endres i ettertid | Publiserte svar og avklaringer kan ikke endres eller slettes, heller ikke av deg. |
| Leverandør fyller portalen med spørsmål | Maks 20 spørsmål per leverandør, og bare frem til frist for spørsmål. |
| Ufullstendige tilbud | Databasen avviser tilbud uten byggetid, oppstart, timepris og bekreftelse av kravene. |
| Noen stjeler passordet ditt | Alt krever tofaktor. Uten det ser du ingenting, selv med riktig passord. |
| Tilbud etter fristen | Databasen avviser det, uansett hva nettsiden sier. |
| Tildeling uten grunn | Velger du ikke laveste tilbud, må du skrive begrunnelse. Det lagres. |

## Hva som er testet – og hva som ikke er det

- **Databasen:** kjørt i ekte Postgres med 117 tester av tilgangsreglene, rollene, de nye feltene, spørsmål og svar og utsending. Alle bestått.
- **Nettsiden:** klikket gjennom hele løpet i Chrome, på mobil- og PC-bredde, i demo-modus. Det gjelder også stegene, de nye leverandørfeltene, sammenligningen, spørsmål og svar, utsendingen av e-post og alle rollene: admin, ekstern og intern takstmann, og bruker uten tilgang.
- **Ikke testet:** koblingen mot et ekte Supabase-prosjekt (innlogging og tofaktor). Koden følger Supabase sin dokumentasjon, men første oppkobling kan trenge en liten justering.

## Kjente begrensninger i demoen

- E-post sendes fra ditt eget e-postprogram, ikke fra portalen. Det er et bevisst valg (se «Slik inviterer du leverandører»).
- Ingen vedlegg (tegninger, bilder). Kan legges til med Supabase Storage.
- Konkurransegrunnlaget som eget dokument (PDF) er ikke med ennå. Leverandøren ser innholdet på nettsiden i stedet.
- Fremdriftsplan kan ikke lastes opp, siden det ikke er vedlegg ennå.
- Gratisversjonen av Supabase pauser prosjektet etter en uke uten bruk. Du starter det igjen med ett klikk.
