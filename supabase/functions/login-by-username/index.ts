// Secure username login bridge. Keeps email lookup on the server.
// Configure SUPABASE_URL, SUPABASE_ANON_KEY and SUPABASE_SERVICE_ROLE_KEY as Edge Function secrets.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { corsHeaders } from '../_shared/cors.ts';
Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return new Response(JSON.stringify({ error: 'Method not allowed' }), { status: 405, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
  try {
    const { username, password } = await req.json();
    if (typeof username !== 'string' || !/^[A-Za-z0-9_.]{3,24}$/.test(username.replace(/^@/, '')) || typeof password !== 'string' || username.length < 3 || username.length > 24 || password.length < 1 || password.length > 256) {
      return new Response(JSON.stringify({ error: 'Credenciales inválidas.' }), { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }
    const url = Deno.env.get('SUPABASE_URL')!;
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!;
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
    const cleanUsername = username.replace(/^@/, '');
    const { data: profile, error: profileError } = await admin.from('profiles').select('id').ilike('username', cleanUsername).maybeSingle();
    if (profileError) throw profileError;
    if (!profile?.id) return new Response(JSON.stringify({ error: 'Credenciales inválidas.' }), { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    const { data: userResult, error: userError } = await admin.auth.admin.getUserById(profile.id);
    if (userError) throw userError;
    const user = userResult.user;
    if (!user?.email) return new Response(JSON.stringify({ error: 'Credenciales inválidas.' }), { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    const authResponse = await fetch(`${url}/auth/v1/token?grant_type=password`, {
      method: 'POST', headers: { 'Content-Type': 'application/json', apikey: anonKey }, body: JSON.stringify({ email: user.email, password })
    });
    const session = await authResponse.json();
    if (!authResponse.ok) return new Response(JSON.stringify({ error: 'Credenciales inválidas.' }), { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    return new Response(JSON.stringify({ session }), { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
  } catch (error) {
    console.error('login-by-username failed', error?.message || error);
    return new Response(JSON.stringify({ error: 'No se pudo iniciar sesión. Inténtalo de nuevo.' }), { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
  }
});
