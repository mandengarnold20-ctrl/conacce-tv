// Conacce TV — régie : ouvre un envoi direct d'une vidéo vers Cloudflare Stream (même plus de 2 Go).
// La clé Cloudflare reste ici, sur le serveur : la page admin ne la voit jamais.
// Secrets à créer dans Supabase (Edge Functions › Secrets) : CLOUDFLARE_ACCOUNT_ID et CLOUDFLARE_API_TOKEN
// (jeton Cloudflare avec la permission « Stream : Edit »).
import { createClient } from 'npm:@supabase/supabase-js@2';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } });
const b64 = (s: string) => btoa(String.fromCharCode(...new TextEncoder().encode(s)));

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  const token = Deno.env.get('CLOUDFLARE_API_TOKEN');
  const account = Deno.env.get('CLOUDFLARE_ACCOUNT_ID');
  if (!token || !account) return json({ error: 'not_configured' }, 503);

  // Seuls les administrateurs peuvent envoyer des vidéos.
  const sb = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!, {
    global: { headers: { Authorization: req.headers.get('Authorization') ?? '' } },
  });
  const { data: isAdmin, error } = await sb.rpc('is_admin');
  if (error || !isAdmin) return json({ error: 'forbidden' }, 403);

  const { size, name, duration } = await req.json().catch(() => ({}));
  if (!size || size <= 0) return json({ error: 'bad_request' }, 400);
  const meta = [`name ${b64(String(name || 'video'))}`];
  if (duration > 0) meta.push(`maxdurationseconds ${b64(String(Math.ceil(duration) + 120))}`);

  const r = await fetch(`https://api.cloudflare.com/client/v4/accounts/${account}/stream?direct_user=true`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      'Tus-Resumable': '1.0.0',
      'Upload-Length': String(size),
      'Upload-Metadata': meta.join(','),
    },
  });
  if (!r.ok) return json({ error: 'cloudflare', status: r.status, detail: (await r.text()).slice(0, 400) }, 502);
  return json({ url: r.headers.get('Location'), uid: r.headers.get('stream-media-id') });
});
