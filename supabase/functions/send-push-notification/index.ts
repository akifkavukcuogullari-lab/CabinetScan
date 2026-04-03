import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { corsHeaders } from '../_shared/cors.ts'
import { supabaseAdmin } from '../_shared/supabase.ts'

// Base64URL encode (no padding, URL-safe)
function base64url(data: Uint8Array | string): string {
  const bytes = typeof data === 'string' ? new TextEncoder().encode(data) : data
  const base64 = btoa(String.fromCharCode(...bytes))
  return base64.replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
}

interface PushRequest {
  user_id: string
  title: string
  body: string
  data?: Record<string, string>
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const { user_id, title, body, data }: PushRequest = await req.json()

    if (!user_id || !title || !body) {
      return new Response(
        JSON.stringify({ error: 'Missing user_id, title, or body' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Get APNs config
    const keyId = Deno.env.get('APNS_KEY_ID')
    const teamId = Deno.env.get('APNS_TEAM_ID')
    const privateKeyB64 = Deno.env.get('APNS_PRIVATE_KEY')
    const bundleId = Deno.env.get('APNS_BUNDLE_ID') ?? 'ai.nextlyn.showroomstaff'

    if (!keyId || !teamId || !privateKeyB64) {
      console.warn('APNs secrets not configured — skipping push')
      return new Response(
        JSON.stringify({ success: true, skipped: true, reason: 'APNs not configured' }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Look up active iOS device tokens for this user
    const { data: tokens, error: tokensError } = await supabaseAdmin
      .from('device_tokens')
      .select('id, device_token')
      .eq('user_id', user_id)
      .eq('platform', 'ios')
      .eq('is_active', true)

    if (tokensError || !tokens || tokens.length === 0) {
      console.log('No active iOS tokens for user', user_id)
      return new Response(
        JSON.stringify({ success: true, sent: 0 }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Build APNs JWT
    const jwt = await buildApnsJwt(keyId, teamId, privateKeyB64)

    // Also look up project_id from design_request if available
    let projectId: string | undefined
    if (data?.design_request_id) {
      const { data: dr } = await supabaseAdmin
        .from('design_requests')
        .select('project_id')
        .eq('id', data.design_request_id)
        .single()
      projectId = dr?.project_id
    }

    const payload = JSON.stringify({
      aps: {
        alert: { title, body },
        sound: 'default',
        badge: 1,
      },
      project_id: projectId,
      ...data,
    })

    // Use sandbox for dev, production for release
    const apnsHost = 'https://api.sandbox.push.apple.com'

    let sent = 0
    for (const { id, device_token } of tokens) {
      try {
        const resp = await fetch(`${apnsHost}/3/device/${device_token}`, {
          method: 'POST',
          headers: {
            authorization: `bearer ${jwt}`,
            'apns-topic': bundleId,
            'apns-push-type': 'alert',
            'apns-priority': '10',
            'content-type': 'application/json',
          },
          body: payload,
        })

        if (resp.status === 200) {
          console.log(`Push sent to ${device_token.substring(0, 8)}...`)
          sent++
        } else {
          const errBody = await resp.text()
          console.error(`APNs ${resp.status} for ${device_token.substring(0, 8)}...: ${errBody}`)

          if (resp.status === 410 || (resp.status === 400 && errBody.includes('BadDeviceToken'))) {
            await supabaseAdmin
              .from('device_tokens')
              .update({ is_active: false })
              .eq('id', id)
            console.log(`Deactivated token ${device_token.substring(0, 8)}...`)
          }
        }
      } catch (err) {
        console.error(`Push error for ${device_token.substring(0, 8)}...:`, err)
      }
    }

    return new Response(
      JSON.stringify({ success: true, sent }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  } catch (error) {
    console.error('Push notification error:', error)
    return new Response(
      JSON.stringify({ error: 'Internal server error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})

// Build ES256 JWT for APNs authentication
async function buildApnsJwt(keyId: string, teamId: string, privateKeyB64: string): Promise<string> {
  const pemText = atob(privateKeyB64)
  const pemBody = pemText
    .replace('-----BEGIN PRIVATE KEY-----', '')
    .replace('-----END PRIVATE KEY-----', '')
    .replace(/\s/g, '')

  const keyData = Uint8Array.from(atob(pemBody), (c) => c.charCodeAt(0))

  const key = await crypto.subtle.importKey(
    'pkcs8',
    keyData,
    { name: 'ECDSA', namedCurve: 'P-256' },
    false,
    ['sign']
  )

  const now = Math.floor(Date.now() / 1000)
  const header = base64url(new TextEncoder().encode(JSON.stringify({ alg: 'ES256', kid: keyId })))
  const claims = base64url(new TextEncoder().encode(JSON.stringify({ iss: teamId, iat: now })))

  const signingInput = `${header}.${claims}`
  const signature = await crypto.subtle.sign(
    { name: 'ECDSA', hash: 'SHA-256' },
    key,
    new TextEncoder().encode(signingInput)
  )

  return `${header}.${claims}.${base64url(new Uint8Array(signature))}`
}
