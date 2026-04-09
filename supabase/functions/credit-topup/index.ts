import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { corsHeaders } from '../_shared/cors.ts'
import { supabaseAdmin } from '../_shared/supabase.ts'
import { stripe, isStripeConfigured, DASHBOARD_URL } from '../_shared/stripe.ts'

const PRESET_AMOUNTS = [2000, 5000, 10000, 50000] // $20, $50, $100, $500

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    if (!isStripeConfigured() || !stripe) {
      return new Response(
        JSON.stringify({ error: 'Stripe is not configured' }),
        { status: 503, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Auth
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: 'Authorization required' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const token = authHeader.replace('Bearer ', '')
    const { data: { user }, error: authError } = await supabaseAdmin.auth.getUser(token)
    if (authError || !user) {
      return new Response(
        JSON.stringify({ error: 'Invalid token' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const { showroom_id, amount_cents } = await req.json()

    if (!showroom_id || !amount_cents || amount_cents < 100) {
      return new Response(
        JSON.stringify({ error: 'showroom_id and amount_cents (min 100) are required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Verify showroom access
    const { data: showroomUser, error: accessError } = await supabaseAdmin
      .from('showroom_users')
      .select('id')
      .eq('user_id', user.id)
      .eq('showroom_id', showroom_id)
      .eq('is_active', true)
      .single()

    if (accessError || !showroomUser) {
      return new Response(
        JSON.stringify({ error: 'Access denied' }),
        { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Get showroom for Stripe customer
    const { data: showroom } = await supabaseAdmin
      .from('showrooms')
      .select('id, name, email, stripe_customer_id')
      .eq('id', showroom_id)
      .single()

    if (!showroom) {
      return new Response(
        JSON.stringify({ error: 'Showroom not found' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Get or create Stripe customer
    let customerId = showroom.stripe_customer_id
    if (!customerId) {
      const customer = await stripe.customers.create({
        email: showroom.email,
        name: showroom.name,
        metadata: { showroom_id: showroom.id },
      })
      customerId = customer.id
      await supabaseAdmin
        .from('showrooms')
        .update({ stripe_customer_id: customerId })
        .eq('id', showroom.id)
    }

    // Create one-time payment checkout session
    const dollars = (amount_cents / 100).toFixed(2)
    const session = await stripe.checkout.sessions.create({
      customer: customerId,
      mode: 'payment',
      payment_method_types: ['card'],
      line_items: [
        {
          price_data: {
            currency: 'usd',
            product_data: {
              name: `CabinetScan Credit Top-Up — $${dollars}`,
              description: `Add $${dollars} to your voice agent & design credit balance`,
            },
            unit_amount: amount_cents,
          },
          quantity: 1,
        },
      ],
      success_url: `${DASHBOARD_URL}/showroom/billing?topup=success`,
      cancel_url: `${DASHBOARD_URL}/showroom/billing?topup=canceled`,
      metadata: {
        credit_topup: 'true',
        showroom_id: showroom.id,
        amount_cents: String(amount_cents),
      },
    })

    return new Response(
      JSON.stringify({ session_id: session.id, url: session.url }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  } catch (error) {
    console.error('[CREDIT_TOPUP] Error:', error)
    return new Response(
      JSON.stringify({ error: 'Internal server error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
