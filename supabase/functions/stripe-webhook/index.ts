import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { corsHeaders } from '../_shared/cors.ts'
import { supabaseAdmin } from '../_shared/supabase.ts'
import { stripe, verifyWebhookSignature, isStripeConfigured } from '../_shared/stripe.ts'
import Stripe from 'https://esm.sh/stripe@14.12.0?target=deno'

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 })
  }

  // Check if Stripe is configured
  if (!isStripeConfigured() || !stripe) {
    console.error('Stripe webhook received but Stripe is not configured')
    return new Response('Stripe not configured', { status: 503 })
  }

  try {
    const body = await req.text()
    const signature = req.headers.get('stripe-signature')

    if (!signature) {
      console.error('No stripe-signature header')
      return new Response('No signature', { status: 400 })
    }

    // Verify webhook signature
    const event = await verifyWebhookSignature(body, signature)

    if (!event) {
      console.error('Invalid webhook signature')
      return new Response('Invalid signature', { status: 400 })
    }

    console.log(`Processing Stripe event: ${event.type}`)

    // Handle different event types
    switch (event.type) {
      case 'checkout.session.completed':
        await handleCheckoutCompleted(event.data.object as Stripe.Checkout.Session)
        break

      case 'customer.subscription.created':
      case 'customer.subscription.updated':
        await handleSubscriptionUpdated(event.data.object as Stripe.Subscription)
        break

      case 'customer.subscription.deleted':
        await handleSubscriptionDeleted(event.data.object as Stripe.Subscription)
        break

      case 'invoice.paid':
        await handleInvoicePaid(event.data.object as Stripe.Invoice)
        break

      case 'invoice.payment_failed':
        await handleInvoicePaymentFailed(event.data.object as Stripe.Invoice)
        break

      default:
        console.log(`Unhandled event type: ${event.type}`)
    }

    return new Response(JSON.stringify({ received: true }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    })
  } catch (error) {
    console.error('Webhook error:', error)
    return new Response('Webhook handler failed', { status: 500 })
  }
})

async function handleCheckoutCompleted(session: Stripe.Checkout.Session) {
  const showroomId = session.metadata?.showroom_id
  const planSlug = session.metadata?.plan_slug
  const planId = session.metadata?.plan_id

  if (!showroomId) {
    console.error('No showroom_id in checkout session metadata')
    return
  }

  console.log(`Checkout completed for showroom: ${showroomId}, plan: ${planSlug}`)

  // Update showroom with subscription info
  await supabaseAdmin
    .from('showrooms')
    .update({
      subscription_status: 'active',
      subscription_plan: planSlug,
      subscription_plan_id: planId || null,
      stripe_subscription_id: session.subscription as string,
      trial_ends_at: null,
    })
    .eq('id', showroomId)

  // Record subscription history
  await supabaseAdmin.from('subscription_history').insert({
    showroom_id: showroomId,
    event_type: 'created',
    to_plan_id: planId || null,
    details: {
      checkout_session_id: session.id,
      plan_slug: planSlug,
    },
    stripe_event_id: session.id,
  })
}

async function handleSubscriptionUpdated(subscription: Stripe.Subscription) {
  const showroomId = subscription.metadata?.showroom_id

  if (!showroomId) {
    // Try to find showroom by customer ID
    const customerId = subscription.customer as string
    const { data: showroom } = await supabaseAdmin
      .from('showrooms')
      .select('id')
      .eq('stripe_customer_id', customerId)
      .single()

    if (!showroom) {
      console.error('Cannot find showroom for subscription:', subscription.id)
      return
    }
  }

  const targetShowroomId = showroomId || (await getShowroomByCustomer(subscription.customer as string))

  if (!targetShowroomId) return

  // Map Stripe status to our status
  const statusMap: Record<string, string> = {
    active: 'active',
    trialing: 'trial',
    past_due: 'past_due',
    canceled: 'canceled',
    unpaid: 'past_due',
    incomplete: 'trial',
    incomplete_expired: 'canceled',
    paused: 'suspended',
  }

  const newStatus = statusMap[subscription.status] || 'active'

  await supabaseAdmin
    .from('showrooms')
    .update({
      subscription_status: newStatus,
      stripe_subscription_id: subscription.id,
      current_period_start: new Date(subscription.current_period_start * 1000).toISOString(),
      current_period_end: new Date(subscription.current_period_end * 1000).toISOString(),
      cancel_at_period_end: subscription.cancel_at_period_end,
      canceled_at: subscription.canceled_at
        ? new Date(subscription.canceled_at * 1000).toISOString()
        : null,
    })
    .eq('id', targetShowroomId)

  // Note: Project count is now reset monthly via pg_cron job (1st of each month)
  // See migration 055_monthly_project_count_reset.sql
}

async function handleSubscriptionDeleted(subscription: Stripe.Subscription) {
  const showroomId = subscription.metadata?.showroom_id ||
    (await getShowroomByCustomer(subscription.customer as string))

  if (!showroomId) return

  await supabaseAdmin
    .from('showrooms')
    .update({
      subscription_status: 'canceled',
      stripe_subscription_id: null,
      canceled_at: new Date().toISOString(),
    })
    .eq('id', showroomId)

  // Record subscription history
  await supabaseAdmin.from('subscription_history').insert({
    showroom_id: showroomId,
    event_type: 'canceled',
    details: {
      subscription_id: subscription.id,
      reason: subscription.cancellation_details?.reason,
    },
    stripe_event_id: subscription.id,
  })
}

async function handleInvoicePaid(invoice: Stripe.Invoice) {
  const customerId = invoice.customer as string
  const showroomId = await getShowroomByCustomer(customerId)

  if (!showroomId) return

  // Create invoice record
  await supabaseAdmin.from('invoices').insert({
    showroom_id: showroomId,
    stripe_invoice_id: invoice.id,
    stripe_payment_intent_id: invoice.payment_intent as string,
    invoice_number: invoice.number || `INV-${Date.now()}`,
    status: 'paid',
    subtotal_cents: invoice.subtotal,
    tax_cents: invoice.tax || 0,
    total_cents: invoice.total,
    amount_paid_cents: invoice.amount_paid,
    amount_due_cents: 0,
    currency: invoice.currency,
    period_start: new Date(invoice.period_start * 1000).toISOString(),
    period_end: new Date(invoice.period_end * 1000).toISOString(),
    paid_at: new Date().toISOString(),
    invoice_pdf_url: invoice.invoice_pdf,
    hosted_invoice_url: invoice.hosted_invoice_url,
    line_items: invoice.lines?.data || [],
  })
}

async function handleInvoicePaymentFailed(invoice: Stripe.Invoice) {
  const customerId = invoice.customer as string
  const showroomId = await getShowroomByCustomer(customerId)

  if (!showroomId) return

  // Update showroom status
  await supabaseAdmin
    .from('showrooms')
    .update({ subscription_status: 'past_due' })
    .eq('id', showroomId)

  // Record subscription history
  await supabaseAdmin.from('subscription_history').insert({
    showroom_id: showroomId,
    event_type: 'payment_failed',
    details: {
      invoice_id: invoice.id,
      amount_due: invoice.amount_due,
      attempt_count: invoice.attempt_count,
    },
    stripe_event_id: invoice.id,
  })
}

async function getShowroomByCustomer(customerId: string): Promise<string | null> {
  const { data: showroom } = await supabaseAdmin
    .from('showrooms')
    .select('id')
    .eq('stripe_customer_id', customerId)
    .single()

  return showroom?.id || null
}
