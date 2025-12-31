import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { corsHeaders } from '../_shared/cors.ts'
import { supabaseAdmin } from '../_shared/supabase.ts'
import { stripe, isStripeConfigured, PRICE_IDS, DASHBOARD_URL } from '../_shared/stripe.ts'

interface CheckoutRequest {
  showroom_id: string
  plan_slug: 'basic' | 'pro'
  billing_period: 'monthly' | 'yearly'
  success_url?: string
  cancel_url?: string
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

    const body: CheckoutRequest = await req.json()

    // Validate request
    if (!body.showroom_id || !body.plan_slug || !body.billing_period) {
      return new Response(
        JSON.stringify({ error: 'showroom_id, plan_slug, and billing_period are required' }),
        {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        }
      )
    }

    // Verify user has access to this showroom
    const { data: showroomUser, error: accessError } = await supabaseAdmin
      .from('showroom_users')
      .select('id, showroom_id')
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

    // Get showroom details
    const { data: showroom, error: showroomError } = await supabaseAdmin
      .from('showrooms')
      .select('id, name, email, stripe_customer_id')
      .eq('id', body.showroom_id)
      .single()

    if (showroomError || !showroom) {
      return new Response(
        JSON.stringify({ error: 'Showroom not found' }),
        {
          status: 404,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        }
      )
    }

    // Get or create Stripe customer
    let customerId = showroom.stripe_customer_id

    if (!customerId) {
      const customer = await stripe.customers.create({
        email: showroom.email,
        name: showroom.name,
        metadata: {
          showroom_id: showroom.id,
        },
      })
      customerId = customer.id

      // Save customer ID
      await supabaseAdmin
        .from('showrooms')
        .update({ stripe_customer_id: customerId })
        .eq('id', showroom.id)
    }

    // Determine price ID
    const priceKey = `${body.plan_slug}_${body.billing_period}` as keyof typeof PRICE_IDS
    const priceId = PRICE_IDS[priceKey]

    if (!priceId) {
      return new Response(
        JSON.stringify({
          error: 'Price not configured',
          message: `Please configure STRIPE_PRICE_${body.plan_slug.toUpperCase()}_${body.billing_period.toUpperCase()} environment variable`,
        }),
        {
          status: 503,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        }
      )
    }

    // Get plan details from database
    const { data: plan } = await supabaseAdmin
      .from('subscription_plans')
      .select('id, name')
      .eq('slug', body.plan_slug)
      .single()

    // Create Stripe Checkout Session
    const session = await stripe.checkout.sessions.create({
      customer: customerId,
      mode: 'subscription',
      payment_method_types: ['card'],
      line_items: [
        {
          price: priceId,
          quantity: 1,
        },
      ],
      success_url: body.success_url || `${DASHBOARD_URL}/showroom/billing?success=true`,
      cancel_url: body.cancel_url || `${DASHBOARD_URL}/showroom/billing?canceled=true`,
      metadata: {
        showroom_id: showroom.id,
        plan_slug: body.plan_slug,
        plan_id: plan?.id || '',
      },
      subscription_data: {
        metadata: {
          showroom_id: showroom.id,
          plan_slug: body.plan_slug,
          plan_id: plan?.id || '',
        },
      },
      allow_promotion_codes: true,
      billing_address_collection: 'required',
    })

    return new Response(
      JSON.stringify({
        session_id: session.id,
        url: session.url,
      }),
      {
        status: 200,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      }
    )
  } catch (error) {
    console.error('Error creating checkout session:', error)
    return new Response(
      JSON.stringify({
        error: 'Internal server error',
        details: error instanceof Error ? error.message : String(error),
        stack: error instanceof Error ? error.stack : undefined
      }),
      {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      }
    )
  }
})
