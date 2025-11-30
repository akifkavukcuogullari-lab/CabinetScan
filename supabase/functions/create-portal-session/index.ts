import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { corsHeaders } from '../_shared/cors.ts'
import { supabaseAdmin } from '../_shared/supabase.ts'
import { stripe, isStripeConfigured, DASHBOARD_URL } from '../_shared/stripe.ts'

interface PortalRequest {
  showroom_id: string
  return_url?: string
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  if (req.method !== 'POST') {
    return new Response(
      JSON.stringify({ error: 'Method not allowed' }),
      {
        status: 405,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      }
    )
  }

  try {
    // Check if Stripe is configured
    if (!isStripeConfigured() || !stripe) {
      return new Response(
        JSON.stringify({
          error: 'Stripe is not configured',
          message: 'Please configure Stripe credentials to enable billing',
          setup_required: true,
        }),
        {
          status: 503,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        }
      )
    }

    // Verify authorization
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: 'Authorization required' }),
        {
          status: 401,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        }
      )
    }

    // Get user from token
    const token = authHeader.replace('Bearer ', '')
    const { data: { user }, error: authError } = await supabaseAdmin.auth.getUser(token)

    if (authError || !user) {
      return new Response(
        JSON.stringify({ error: 'Invalid token' }),
        {
          status: 401,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        }
      )
    }

    const body: PortalRequest = await req.json()

    if (!body.showroom_id) {
      return new Response(
        JSON.stringify({ error: 'showroom_id is required' }),
        {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        }
      )
    }

    // Verify user has access to this showroom
    const { data: showroomUser, error: accessError } = await supabaseAdmin
      .from('showroom_users')
      .select('id')
      .eq('user_id', user.id)
      .eq('showroom_id', body.showroom_id)
      .eq('is_active', true)
      .single()

    if (accessError || !showroomUser) {
      return new Response(
        JSON.stringify({ error: 'Access denied to this showroom' }),
        {
          status: 403,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        }
      )
    }

    // Get showroom's Stripe customer ID
    const { data: showroom, error: showroomError } = await supabaseAdmin
      .from('showrooms')
      .select('stripe_customer_id')
      .eq('id', body.showroom_id)
      .single()

    if (showroomError || !showroom?.stripe_customer_id) {
      return new Response(
        JSON.stringify({
          error: 'No billing account found',
          message: 'Please subscribe to a plan first',
        }),
        {
          status: 404,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        }
      )
    }

    // Create Stripe Customer Portal session
    const session = await stripe.billingPortal.sessions.create({
      customer: showroom.stripe_customer_id,
      return_url: body.return_url || `${DASHBOARD_URL}/showroom/billing`,
    })

    return new Response(
      JSON.stringify({ url: session.url }),
      {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      }
    )
  } catch (error) {
    console.error('Error creating portal session:', error)
    return new Response(
      JSON.stringify({ error: 'Internal server error' }),
      {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      }
    )
  }
})
