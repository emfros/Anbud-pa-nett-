// =====================================================================
//  Edge Function «vedlegg-lenker»
//  Gir leverandøren lenker til vedleggene på anbudet – etter at koden er sjekket.
//  Lenkene varer i en time. Service-nøkkelen brukes bare her, på serveren,
//  og kommer aldri ut i nettsiden.
//
//  Supabase legger SUPABASE_URL og SUPABASE_SERVICE_ROLE_KEY inn automatisk.
//  Oppsett: se LES-MEG.md, avsnittet «Vedlegg».
// =====================================================================

const VARIGHET = 3600; // sekunder (1 time)

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const svar = (data: unknown, status = 200) =>
  new Response(JSON.stringify(data), { status, headers: { ...cors, 'Content-Type': 'application/json' } });

type Fil = { id: string; sti: string };

export async function behandle(req: Request, lagKlient: () => Promise<any> = standardKlient): Promise<Response> {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return svar({ ok: false, feil: 'Bruk POST.' }, 405);

  let kode = '';
  try {
    const body = await req.json();
    kode = typeof body?.kode === 'string' ? body.kode : '';
  } catch {
    return svar({ ok: false, feil: 'Ugyldig forespørsel.' }, 400);
  }
  if (!kode || kode.length > 40) return svar({ ok: false, feil: 'Koden er ikke gyldig.' }, 400);

  try {
    const sb = await lagKlient();
    // Databasen sjekker koden og gir bare stiene til dette anbudets aktive vedlegg
    const { data, error } = await sb.rpc('vedlegg_for_kode', { p_kode: kode });
    if (error) throw error;
    if (!data?.ok) return svar({ ok: false, feil: data?.feil || 'Koden er ikke gyldig.' });

    const filer: Fil[] = data.filer || [];
    if (!filer.length) return svar({ ok: true, lenker: {}, varighet: VARIGHET });

    const { data: signert, error: feil } = await sb.storage.from('vedlegg')
      .createSignedUrls(filer.map((f) => f.sti), VARIGHET);
    if (feil) throw feil;

    const lenker: Record<string, string> = {};
    for (const f of filer) {
      const s = (signert || []).find((x: any) => x.path === f.sti);
      if (s?.signedUrl) lenker[f.id] = s.signedUrl;
    }
    return svar({ ok: true, lenker, varighet: VARIGHET });
  } catch (e) {
    console.error(e);
    return svar({ ok: false, feil: 'Kunne ikke hente vedleggene. Prøv igjen.' }, 500);
  }
}

async function standardKlient() {
  const { createClient } = await import('npm:@supabase/supabase-js@2.45.4');
  // @ts-ignore Deno finnes i Supabase Edge Functions
  return createClient(Deno.env.get('SUPABASE_URL'), Deno.env.get('SUPABASE_SERVICE_ROLE_KEY'), {
    auth: { persistSession: false },
  });
}

// @ts-ignore Deno finnes i Supabase Edge Functions
if (typeof Deno !== 'undefined') Deno.serve((req: Request) => behandle(req));
