# Anbudsportal – slik setter du den opp

Fire filer:

- **index.html** – hele nettsiden. Står nøklene øverst tomme, kjører den som demo.
- **oppsett.sql** – databasen med alle tilgangsregler.
- **supabase/functions/vedlegg-lenker/index.ts** – en liten serverfunksjon som gir leverandørene lenker til vedleggene.
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

## 4. Sett opp vedlegg (serverfunksjonen)

Vedleggene ligger i en lukket «bøtte» (mappe for filer) i Supabase. `oppsett.sql` lager den.
Storebrand og takstmenn får tilgang gjennom innloggingen. Leverandørene har ingen innlogging, så de får lenkene fra en liten serverfunksjon (Edge Function) som sjekker koden først.

1. Sjekk at bøtta finnes: gå til **Storage**. Der skal det ligge en bøtte som heter **vedlegg**, merket **Private**.
2. Gå til **Edge Functions** → **Deploy a new function** → **Via Editor**.
3. Kall funksjonen **vedlegg-lenker** (nøyaktig slik, med bindestrek).
4. Slett eksempelkoden. Lim inn hele innholdet i `supabase/functions/vedlegg-lenker/index.ts`. Trykk **Deploy**.
5. Du trenger ikke legge inn noen nøkler. Supabase gir funksjonen adressen og service-nøkkelen selv. Den nøkkelen blir på serveren og kommer aldri ut i nettsiden.
6. Test: åpne et anbud med vedlegg som leverandør. Står det «Fikk ikke hentet vedleggene», åpner du funksjonen i Supabase og ser under **Logs**. Står det **401** der, går du til funksjonens **Settings** (eller **Details**) og slår **av** «Verify JWT» (kan hete «Enforce JWT verification»). Det er trygt: funksjonen sjekker leverandørkoden selv og gir ingenting uten riktig kode.

## 5. Legg nettsiden ut (Netlify)

1. Lag en mappe som bare inneholder `index.html`.
2. Gå til **app.netlify.com/drop** og dra mappen inn i nettleseren.
3. Du får en adresse som `noe-tilfeldig.netlify.app`. Siden virker allerede der, med HTTPS (kryptert tilkobling).

Når du endrer `index.html` senere: dra mappen inn på nytt under **Deploys** i Netlify.

## 6. Koble på ditt eget domene

1. Kjøp domenet, for eksempel hos **Domeneshop**.
2. I Netlify: **Domain management** → **Add a domain** → skriv inn domenet.
3. Netlify viser hvilke DNS-oppføringer du skal legge inn. DNS er «telefonkatalogen» som forteller nettet hvor domenet ditt bor. Hos Domeneshop legger du dem inn under **DNS**. Vanligvis:
   - `www` → **CNAME** → `noe-tilfeldig.netlify.app`
   - selve domenet → **A** → IP-adressen Netlify oppgir
4. Vent fra noen minutter til noen timer. Netlify lager HTTPS-sertifikatet selv.
5. Tilbake i Supabase: **Authentication** → **URL Configuration**. Sett **Site URL** til `https://ditt-domene.no`.

## 7. Test hele løpet

1. Gå til `https://ditt-domene.no/#intern` og logg inn. Sett opp tofaktor. Lagre adressen som bokmerke. Forsiden uten `#intern` er for leverandørene og har bare kodefeltet.
2. Lag et anbud med oppdiktede data og send det ut.
3. Inviter deg selv som leverandør. Kopier koden.
4. Åpne siden i et **privat vindu** og skriv inn koden. Lever et tilbud.
5. Gå tilbake som admin. Tilbudet skal ligge der. Tildel det og sjekk **Årsoversikt**.
   Før du tildeler: last opp en PDF og et bilde under **Vedlegg**, og sjekk i det private vinduet at leverandøren kan åpne begge.
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

**Den som lager anbudet** (admin eller takstmann) fyller ut sju steg:

1. **Saken** – skadenummer, skadetype, adresse og hva som skal anskaffes.
2. **Takstmann og kontakt** – hvem leverandørene sender spørsmål til.
3. **Befaring og frister** – befaring, frist for spørsmål, tilbudsfrist og vedståelsesfrist (hvor lenge leverandøren må stå ved prisen).
4. **Beskrivelse av arbeidet** – arbeidsomfang og særlige forhold. Under arbeidsomfanget ligger knapper med **standardtekster** (TEK17, SHA-plan, SJA, avfallsplan, våtrom, asbest, FDV og flere). Trykk på en knapp, så settes teksten inn som eget avsnitt der markøren står i arbeidsomfanget. Står ikke markøren der, havner teksten nederst. Trykk en gang til, så tas den bort. Tekstene endrer du i `ARBEIDSTEKSTER` øverst i `index.html`. Faste krav står alltid med. Her krysser du også av for **presiseringer** (ferdige setninger om hva prisen omfatter, varsling, fukt, standardheving og faktura) og for om leverandøren må fylle ut fremdriftsplan. Fremdriftsplan er på som standard. Presiseringene endrer du i `STANDARDTEKSTER` øverst i `index.html`.
5. **Bygninger og poster** – mengder per post og din kalkyle. Dra i håndtaket ⠿ for å endre rekkefølgen på bygg og poster. Poster flyttes innenfor sitt eget bygg. Nummereringen følger med.
6. **Vedlegg** – takstrapport, bilder og andre dokumenter (se «Vedlegg» under).
7. **Tildeling** – hvordan leverandør velges.

**Leverandøren** ser alt dette, og fyller ut firma, tidligste oppstart, timepris for tilleggsarbeid, fremdriftsplan, pris per post og forbehold per bygg. Til slutt krysser de av for at tilbudet følger kravene.

Når du sammenligner, ser du byggetid, oppstart, timepris, forbehold og fremdriftsplanene ved siden av prisen.

## Slik er anbudssiden bygget opp

Det du trenger oftest, står øverst:

1. **Tallene** (kalkyle, tilbud levert, laveste tilbud og frist) og knappen **Status til forsikringstaker**.
2. **Tilbud**: kortene, tildeling og pris per post. Fremdriftsplanene ligger lukket under «Fremdriftsplanene».
3. **Spørsmål og svar**. «Legg ut en avklaring» åpnes med en knapp.
4. **Leverandører**: alle invitasjoner, og knappen **+ Inviter flere**.
5. **Vedlegg**. Kategori endres med «Kategori» ved hver fil.
6. **Anbudet** (slik leverandørene ser det) og **Endre frister eller avlys**. Begge er lukket til du trenger dem.

Hos leverandøren er «Krav og tildeling» lukket, med teksten «Les før dere gir pris».

Det du åpner, blir stående åpent til du går til et annet anbud.

## Fremdriftsplan

- **En fast mal for hele saken**, ikke per fag. Seks faser: rigg og tildekking, riving og sanering, uttørking og venting, oppbygging, overflater, rydding og overlevering.
- **Leverandøren velger tidligste oppstart først.** Planen starter der. Ingen fase kan starte før den datoen. Er planen tom, fylles første fase inn med oppstartsdatoen, så kalenderen åpner i riktig måned.
- **Fra- og til-dato per fase.** Ingen uker. Begge dagene teller med. Velger de en fra-dato uten til-dato, settes til-dato lik fra-dato. Faser som ikke er aktuelle, står tomme. Faser kan gå samtidig.
- **Tidslinjen vises hele tiden**, også før noe er fylt inn. Faser uten datoer står med en stiplet rad og teksten «Ikke fylt inn». Uttørking og venting vises med striper, så du ser hvor tiden går med til venting.
- **Ferdigdatoen regnes ut fra planen**, både i nettsiden og i databasen. Det er den siste til-datoen. Leverandøren skriver den ikke selv, så plan og ferdigdato kan ikke vise forskjellige ting. Byggetiden vises i dager fra oppstart.
- **Hos deg** står planene på samme kalender. Den som blir ferdig først, får merket «Ferdig først». Merket står også på tilbudskortet og i tabellen under «Pris per post», der det er en egen rad «Ferdig».
- **Påkrevd som standard.** Du kan krysse det av på steg 4 i små saker. Da oppgir leverandøren bare tidligste oppstart og ferdigdato. Valget låses når anbudet sendes ut.

**Legg i kalender:** Ved befaring og tilbudsfrist er det en knapp som laster ned en kalenderfil (.ics). Den åpnes i Outlook, iPhone, Google Kalender og de fleste andre kalendere, med påminnelse dagen før. Endres befaringen senere, må leverandøren trykke på knappen igjen. Da oppdateres avtalen i stedet for at det blir to.

## Slik inviterer du leverandører

Portalen sender aldri e-post selv. Du sender fra din egen e-post, i tre steg:

1. **Skriv inn firma og e-post**, og trykk «Se e-posten».
2. **Se over e-posten.** Du ser hvem den er fra (deg), hvem den går til, emnet og teksten. Du kan endre alt. `[KODE]` byttes ut med leverandørens personlige kode.
3. **Trykk «Lag kode og åpne e-post».** E-posten åpnes ferdig utfylt i e-postprogrammet ditt, for eksempel Outlook. Du ser over og sender selv. Trykk så «Ja, marker som sendt» i portalen.

Send én e-post per leverandør. Koden er personlig, og leverandørene skal ikke se hvem de konkurrerer med.

E-posten har også en lenke der koden er fylt inn, så leverandøren slipper å skrive den.

Under «Invitasjoner» ser du status for hver leverandør: ikke sendt, sendt, åpnet eller levert.

**Trekk tilbake invitasjon** stenger koden med en gang. Du får et spørsmål før det skjer. Leverandører som allerede har levert, kan ikke trekkes tilbake.

**Lag ny kode** brukes når en leverandør har mistet koden. Den gamle koden slutter å virke med en gang. Tilbud og spørsmål de allerede har sendt, blir liggende. Du får en ferdig e-post med den nye koden, akkurat som ved invitasjon.

**Hvorfor ser jeg bare de fire siste tegnene i koden?** Koden lagres aldri i databasen, bare et fingeravtrykk av den (en hash). Portalen kan sjekke om en kode er riktig, men ikke regne ut selve koden. Slik kan ingen hos Storebrand, eller noen som får tak i databasen, levere eller endre tilbud i en leverandørs navn.

**Hvorfor sender ikke portalen selv?** En e-post med kode fra et ukjent domene som sier at den er fra Storebrand, ser ut som svindel og havner ofte i søppelposten. Skal portalen sende selv, bør det skje fra en Storebrand-adresse, og det krever IT.

## Spørsmål og svar

- **Leverandøren** stiller spørsmål i portalen, frem til frist for spørsmål (eller tilbudsfristen hvis du ikke har satt en egen frist). Maks 20 spørsmål per leverandør.
- **Du** ser hvem som spurte. Før du publiserer, kan du skrive om spørsmålet så det ikke avslører hvem som spør.
- **Svaret publiseres til alle** leverandørene på samme anbud. De ser aldri hvem som spurte.
- Du kan også legge ut en **avklaring** til alle, uten at noen har spurt.
- **Publiserte svar kan ikke endres eller slettes.** Har du skrevet feil, legger du ut en avklaring.
- Leverandøren får beskjed om nye svar siden sist. Kommer det svar etter at de har levert, blir de bedt om å sjekke om tilbudet må endres.
- Det sendes ingen e-post. I listen over anbud ser du hvor mange spørsmål som venter på svar.
- Med knappene øverst kan du vise alle, bare spørsmål eller bare avklaringer. Du har også «Venter på svar».

## Vedlegg

- **Hvem laster opp:** Storebrand og takstmenn, på steg 6 i utkastet eller under «Vedlegg» når anbudet er sendt ut. Et nytt utkast må lagres først.
- **Hva:** PDF, bilder (JPG, PNG, HEIC), Word og Excel. Maks 20 MB per fil og 30 vedlegg per anbud. Andre filer avvises, både av nettsiden og av Supabase.
- **Kategori:** Portalen gjetter (bilde, takstrapport, tegning eller annet). Du kan endre den i listen.
- **Leverandøren** ser vedleggene under arbeidsomfanget. Bilder vises som små bilder, dokumenter med «Last ned». Lenkene virker i én time. Etterpå trykker de «Hent lenker på nytt».
- **Etter utsending** kan du legge til vedlegg. De får rød ramme og merket «Lagt til etter utsending», både hos deg og hos leverandøren. Øverst på leverandørens side kommer en rød boks med navn og dato på filene. Har leverandøren allerede levert, står det at de leverte før vedlegget kom, og at de må sjekke prisen. Når de sender tilbudet, bekrefter de også at de har sett vedleggene. Gi dem gjerne beskjed i tillegg, siden portalen ikke sender e-post.
- **Fjern:** Filen slettes, og leverandørene ser den ikke lenger. Etter utsending blir det stående i listen at vedlegget fantes og når det ble fjernet, så historikken er hel. I et utkast forsvinner det helt.
- **Når saken er tildelt eller avlyst,** kan du ikke legge til flere vedlegg. Du kan fortsatt fjerne, for eksempel hvis noe ble lastet opp ved en feil.
- **Personvern:** Ikke last opp bilder der personer kan kjennes igjen, og fjern kundens navn og telefon fra rapporter før du laster dem opp. Leverandørene ser alt som ligger der.

## Status til forsikringstaker

På et utsendt eller tildelt anbud er det en knapp: **Status til forsikringstaker (PDF)**. Den lager en oversikt du kan legge ved i en e-post til kunden.

- **Før tildeling:** «Vi henter inn tilbud», med tilbudsfrist og eventuell befaring. Står befaringen foran, bes kunden om å være til stede eller låse inn.
- **Etter tildeling:** hvem som skal gjøre jobben, kontaktperson, når de kan starte, ferdig ca., og fremdriftsplanen med datoer.
- **Alltid:** hvor saken står (fem enkle steg), hva som skal gjøres, og hvem kunden kan kontakte. Det er den som er logget inn.
- **Aldri:** priser, kalkyle, besparelse eller andre tilbud.
- **Kundens navn** står ikke i filen, fordi portalen ikke har det. Skriv navnet i e-posten.
- Du kan skrive en personlig hilsen øverst før du lagrer.
- Trykk **Lagre som PDF**, og velg «Lagre som PDF» i utskriftsvinduet. Filen får navnet «Status SB-…».

## Har du allerede satt opp databasen?

Kjør hele `oppsett.sql` på nytt i Supabase. Den lager tabellene på nytt med de nye feltene. **Alle anbud, tilbud og spørsmål blir slettet.** Det går fint så lenge du bare har testdata.

Brukerne og rollene deres blir stående. Det er bare første gang du må gjøre deg selv til admin med SQL-linjen i steg 2.

Filer du har lastet opp, blir liggende i bøtta selv om vedleggslisten slettes. Vil du rydde, går du til **Storage** → **vedlegg** og sletter mappene der. Serverfunksjonen (steg 4) må bare legges inn én gang. Endres `index.ts` senere, limer du inn den nye versjonen og trykker **Deploy** igjen.

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
| Noen gir seg ut for å være leverandør | Koden lagres bare som fingeravtrykk. Ingen kan lese den i databasen, heller ikke admin. Mister leverandøren koden, lager du en ny. |
| E-post går til feil leverandør | Ingenting sendes automatisk. Du ser hver e-post før den sendes, og sender den selv. |
| Leverandør får vite hvem som spurte | Leverandørene ser bare den publiserte teksten, aldri hvem som spurte. Du kan skrive om spørsmålet før du publiserer. |
| Svar endres i ettertid | Publiserte svar og avklaringer kan ikke endres eller slettes, heller ikke av deg. |
| Leverandør fyller portalen med spørsmål | Maks 20 spørsmål per leverandør, og bare frem til frist for spørsmål. |
| Ufullstendige tilbud | Databasen avviser tilbud uten oppstart, ferdigdato, timepris og bekreftelse av kravene. |
| Noen stjeler passordet ditt | Alt krever tofaktor. Uten det ser du ingenting, selv med riktig passord. |
| Tilbud etter fristen | Databasen avviser det, uansett hva nettsiden sier. |
| Tildeling uten grunn | Velger du ikke laveste tilbud, må du skrive begrunnelse. Det lagres. |
| Noen finner vedleggene på nettet | Bøtta er lukket. Ingen fil har en fast, offentlig adresse. Alle lenker er signerte og slutter å virke etter én time. |
| Leverandør ser vedlegg fra andre anbud | Serverfunksjonen sjekker koden og gir bare lenker til vedleggene på det anbudet koden hører til. Leverandøren ser aldri hvor filene ligger. |
| Takstmann ser vedlegg på andres anbud | Tilgangen til filene følger samme regel som anbudet: takstmenn ser bare sine egne. Det sjekkes både i tabellen og i bøtta. |
| Noen laster opp en farlig eller stor fil | Bøtta tar bare PDF, bilder, Word og Excel, maks 20 MB. Supabase avviser resten, uansett hva nettsiden sier. |
| Vedlegg forsvinner sporløst etter utsending | Etter utsending kan vedlegg bare fjernes, ikke slettes. Det står igjen når det ble lagt til og fjernet. |
| Leverandør overser vedlegg som kom etter utsending | Rød boks øverst på siden, rød ramme på filene, og de må bekrefte at de har sett dem før de sender. |
| Presiseringer endres etter at tilbud er gitt | Presiseringene låses i databasen når anbudet sendes ut, sammen med beskrivelse og vilkår. |
| En mengde eller pris leses feil | Tall leses likt i nettsiden og databasen: `1200`, `1 200`, `1.200` og `7,2` virker alle. Databasen sender ikke ut anbud der en mengde ikke er et tall. |
| Ferdigdato og fremdriftsplan stemmer ikke | Ferdigdatoen og antall dager regnes ut fra planen i databasen. Tallene fra nettleseren brukes ikke. |
| Service-nøkkelen lekker | Den brukes bare inne i serverfunksjonen hos Supabase. Den står ikke i nettsiden og ikke i filene på GitHub. |

## Hva som er testet – og hva som ikke er det

- **Databasen:** kjørt i ekte Postgres med 165 tester av tilgangsreglene, rollene, de nye feltene, spørsmål og svar, utsending, ny kode, vedlegg (også tilgangen til selve filene) og fremdriftsplan. Alle bestått.
- **Serverfunksjonen for vedlegg:** 12 tester. Den gir lenker bare ved riktig kode, lenkene varer i én time, og feilmeldingene røper ingen detaljer. Alle bestått.
- **Nettsiden:** klikket gjennom hele løpet i Chrome, på mobil- og PC-bredde, i demo-modus. Det gjelder også stegene, de nye leverandørfeltene, sammenligningen, spørsmål og svar, utsendingen av e-post, kalenderfilene, ny kode, vedlegg (opplasting, dra og slipp, feil filtype, for stor fil, kategori, fjerning, visning og varsel hos leverandøren), fremdriftsplan (utfylling, utregning av byggetid, tidslinje, kvittering og sammenligning), statusfil til forsikringstaker (før og etter tildeling, uten priser) og alle rollene: admin, ekstern og intern takstmann, og bruker uten tilgang.
- **Ikke testet:** koblingen mot et ekte Supabase-prosjekt (innlogging, tofaktor, opplasting til bøtta og serverfunksjonen der). Koden følger Supabase sin dokumentasjon, men første oppkobling kan trenge en liten justering.

## Kjente begrensninger i demoen

- E-post sendes fra ditt eget e-postprogram, ikke fra portalen. Det er et bevisst valg (se «Slik inviterer du leverandører»).
- Konkurransegrunnlaget som eget dokument (PDF) er ikke med ennå. Leverandøren ser innholdet på nettsiden i stedet.
- Leverandøren kan ikke laste opp egne filer. Bare Storebrand og takstmenn laster opp. Fremdriftsplanen fylles ut i malen i stedet.
- I demoen ligger vedleggene bare i nettleseren. De forsvinner når du laster siden på nytt.
- Gratisversjonen av Supabase pauser prosjektet etter en uke uten bruk. Du starter det igjen med ett klikk.
