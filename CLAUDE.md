# Anbudsportal – instrukser til Claude

Nettside der Storebrand lager anbud på byggskader, leverandører gir pris med en kode, og saksbehandler sammenligner tilbud og ser besparelse per år.

## Filene

- `index.html` – hele nettsiden i én fil. Kjører som demo når `SUPABASE_URL` og `SUPABASE_ANON_KEY` øverst i skriptet er tomme.
- `oppsett.sql` – databasen i Supabase: tabeller, tilgangsregler (RLS) og de tre funksjonene leverandørene kaller (hent, send tilbud, still spørsmål).
- `LES-MEG.md` – oppskriften for å sette opp alt, skrevet for Emil.

## Regler

1. **Hold oppskriften oppdatert.** Når en endring påvirker oppsett, innlogging, database, sikkerhet eller hvordan siden brukes, oppdaterer du `LES-MEG.md` i samme branch og i samme omgang. Endrer du databasen, oppdaterer du `oppsett.sql` og tabellen «Hva som beskytter dataene» i `LES-MEG.md`.
2. **Ikke jobb direkte på `main`.** Bruk en branch. `main` er den gjeldende versjonen og endres bare ved merge.
3. **Logikken i `index.html` og `oppsett.sql` hører sammen.** Regler som sjekkes i nettsiden (frist, org.nr, sum, tildeling) skal også sjekkes i databasen. Databasen er den som bestemmer.
4. **Sikkerhet:** Bruk aldri `service_role`-nøkkelen i nettsiden. Kalkylen skal aldri sendes til leverandører. Summen regnes ut på serveren. Ingen kundenavn i data.
5. **Bare oppdiktede data** til IT i Storebrand har godkjent løsningen.
6. **Utseende:** Storebrand-layout (røde farger, Schibsted Grotesk innebygd i filen, Storebrand-logo). Bare lyst tema. Tabelltall (`tabular-nums`) brukes bare på kronebeløp, fordi fonten ellers gjør punktum og komma brede.
7. **Filen skal fungere alene.** Behold `<!doctype html>` og `<meta charset="utf-8">` øverst, ellers blir siden blank når den åpnes som fil i Safari.
8. **Felt som må stemme overens:** `ANBUD_FELT` i `index.html` må ha de samme feltene som tabellen `anbud` i `oppsett.sql`. Feltene som kan endres etter utsending (`ENDRES_ETTER_UTSENDING`) må stemme med låsen i `anbud_vakt`. De faste kravene (`FASTE_KRAV`) og standard tildelingsregel (`STD_TILDELING`) ligger i `index.html`.
9. **Spørsmål og svar:** Leverandørene må aldri få se hvem som spurte, eller ubesvarte spørsmål fra andre. Publiserte svar kan ikke endres eller slettes (låst i `sporsmal_vakt`).
10. **E-post:** Portalen sender aldri e-post selv. Invitasjoner forhåndsvises og åpnes i saksbehandlerens eget e-postprogram (mailto), én e-post per leverandør. Ikke legg inn automatisk utsending uten at Emil og IT har bestemt det.
11. **Test før du lagrer:** Klikk gjennom hele løpet (saksbehandler lager anbud og kode, leverandør stiller spørsmål og leverer, saksbehandler svarer og tildeler, årsoversikt) på mobil- og PC-bredde, uten feil i konsollen.

## Git på Emils Mac

- Mappen heter `Anbud på nett ` (med mellomrom på slutten, og «å» kan være lagret som to tegn). Bruk `cd "$HOME"/mnt/Anbud*` i stedet for å skrive navnet.
- Claude kan lagre endringer (commit), men ikke pushe. Emil pusher med **Push origin** i GitHub Desktop.
- Git legger igjen låsefiler (`.git/*.lock`) hvis Claude ikke har lov til å slette i mappen. Be om slettetilgang før du bruker git.
- Tagger lages i GitHub Desktop (History → høyreklikk → Create Tag). `v1-demo-uten-storebrand` er første demo.

## Hvordan Emil vil ha svar

Enkel, muntlig norsk med korte setninger. Forklar fagord med en gang. Kort og konkret, ett steg om gangen når han skal gjøre noe selv.
