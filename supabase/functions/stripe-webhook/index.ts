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

    console.log(`[WEBHOOK] Processing Stripe event: ${event.type}`)
    console.log(`[WEBHOOK] Event ID: ${event.id}`)

    // Handle different event types
    switch (event.type) {
      case 'checkout.session.completed':
        console.log(`[WEBHOOK] Checkout session data:`, JSON.stringify(event.data.object))
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
  // Route credit top-ups to separate handler
  if (session.metadata?.credit_topup === 'true') {
    await handleCreditTopup(session)
    return
  }

  const showroomId = session.metadata?.showroom_id
  const planSlug = session.metadata?.plan_slug
  const planId = session.metadata?.plan_id

  if (!showroomId) {
    console.error('No showroom_id in checkout session metadata')
    return
  }

  console.log(`[CHECKOUT] Starting update for showroom: ${showroomId}`)
  console.log(`[CHECKOUT] Plan: ${planSlug}, planId: ${planId}`)
  console.log(`[CHECKOUT] Subscription ID: ${session.subscription}`)

  // Update showroom with subscription info and return the updated row
  const { data: updatedShowroom, error: updateError } = await supabaseAdmin
    .from('showrooms')
    .update({
      subscription_status: 'active',
      subscription_plan: planSlug,
      subscription_plan_id: planId || null,
      stripe_subscription_id: session.subscription as string,
      trial_ends_at: null,
    })
    .eq('id', showroomId)
    .select('id, subscription_plan, subscription_plan_id, subscription_status')
    .single()

  if (updateError) {
    console.error(`[CHECKOUT] Failed to update showroom ${showroomId}:`, updateError)
    throw new Error(`Failed to update showroom: ${updateError.message}`)
  }

  if (!updatedShowroom) {
    console.error(`[CHECKOUT] No showroom found with id: ${showroomId}`)
    throw new Error(`Showroom not found: ${showroomId}`)
  }

  console.log(`[CHECKOUT] Successfully updated showroom:`, JSON.stringify(updatedShowroom))

  // Record subscription history
  const { error: historyError } = await supabaseAdmin.from('subscription_history').insert({
    showroom_id: showroomId,
    event_type: 'created',
    to_plan_id: planId || null,
    details: {
      checkout_session_id: session.id,
      plan_slug: planSlug,
    },
    stripe_event_id: session.id,
  })

  if (historyError) {
    console.error(`Failed to record subscription history for ${showroomId}:`, historyError)
    // Don't throw here - history is secondary to the main update
  }

  // Grant one-time plan bonus credits if applicable
  if (planSlug) {
    await grantPlanBonus(showroomId, planSlug, 'one_time')
  }
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

  if (!targetShowroomId) {
    console.error('No showroom found for subscription update:', subscription.id)
    return
  }

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

  console.log(`Subscription updated for showroom ${targetShowroomId}: status=${newStatus}, subscription=${subscription.id}`)

  const { error: updateError } = await supabaseAdmin
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

  if (updateError) {
    console.error(`Failed to update subscription for showroom ${targetShowroomId}:`, updateError)
    throw new Error(`Failed to update subscription: ${updateError.message}`)
  }

  console.log(`Successfully updated subscription status for showroom ${targetShowroomId}`)

  // Note: Project count is now reset monthly via pg_cron job (1st of each month)
  // See migration 055_monthly_project_count_reset.sql
}

async function handleSubscriptionDeleted(subscription: Stripe.Subscription) {
  const showroomId = subscription.metadata?.showroom_id ||
    (await getShowroomByCustomer(subscription.customer as string))

  if (!showroomId) {
    console.error('No showroom found for subscription deletion:', subscription.id)
    return
  }

  console.log(`Subscription deleted for showroom ${showroomId}: ${subscription.id}`)

  const { error: updateError } = await supabaseAdmin
    .from('showrooms')
    .update({
      subscription_status: 'canceled',
      stripe_subscription_id: null,
      canceled_at: new Date().toISOString(),
    })
    .eq('id', showroomId)

  if (updateError) {
    console.error(`Failed to update showroom ${showroomId} on subscription deletion:`, updateError)
    throw new Error(`Failed to update subscription deletion: ${updateError.message}`)
  }

  console.log(`Successfully marked showroom ${showroomId} as canceled`)

  // Record subscription history
  const { error: historyError } = await supabaseAdmin.from('subscription_history').insert({
    showroom_id: showroomId,
    event_type: 'canceled',
    details: {
      subscription_id: subscription.id,
      reason: subscription.cancellation_details?.reason,
    },
    stripe_event_id: subscription.id,
  })

  if (historyError) {
    console.error(`Failed to record cancellation history for ${showroomId}:`, historyError)
  }
}

async function handleInvoicePaid(invoice: Stripe.Invoice) {
  const customerId = invoice.customer as string
  const showroomId = await getShowroomByCustomer(customerId)

  if (!showroomId) {
    console.error('No showroom found for invoice:', invoice.id)
    return
  }

  console.log(`Invoice paid for showroom ${showroomId}: ${invoice.id}`)

  // Create invoice record
  const { error: insertError } = await supabaseAdmin.from('invoices').insert({
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

  if (insertError) {
    console.error(`Failed to record invoice for showroom ${showroomId}:`, insertError)
    // Don't throw - invoice record is secondary
  } else {
    console.log(`Successfully recorded invoice ${invoice.id} for showroom ${showroomId}`)
  }

  // Grant monthly plan bonus credits if applicable
  const { data: showroom } = await supabaseAdmin
    .from('showrooms')
    .select('subscription_plan')
    .eq('id', showroomId)
    .single()

  if (showroom?.subscription_plan) {
    await grantPlanBonus(showroomId, showroom.subscription_plan, 'monthly')
  }
}

async function handleInvoicePaymentFailed(invoice: Stripe.Invoice) {
  const customerId = invoice.customer as string
  const showroomId = await getShowroomByCustomer(customerId)

  if (!showroomId) {
    console.error('No showroom found for failed invoice:', invoice.id)
    return
  }

  console.log(`Invoice payment failed for showroom ${showroomId}: ${invoice.id}, attempt: ${invoice.attempt_count}`)

  // Update showroom status
  const { error: updateError } = await supabaseAdmin
    .from('showrooms')
    .update({ subscription_status: 'past_due' })
    .eq('id', showroomId)

  if (updateError) {
    console.error(`Failed to update showroom ${showroomId} to past_due:`, updateError)
    throw new Error(`Failed to update payment failed status: ${updateError.message}`)
  }

  console.log(`Successfully marked showroom ${showroomId} as past_due`)

  // Record subscription history
  const { error: historyError } = await supabaseAdmin.from('subscription_history').insert({
    showroom_id: showroomId,
    event_type: 'payment_failed',
    details: {
      invoice_id: invoice.id,
      amount_due: invoice.amount_due,
      attempt_count: invoice.attempt_count,
    },
    stripe_event_id: invoice.id,
  })

  if (historyError) {
    console.error(`Failed to record payment failure history for ${showroomId}:`, historyError)
  }
}

async function getShowroomByCustomer(customerId: string): Promise<string | null> {
  const { data: showroom } = await supabaseAdmin
    .from('showrooms')
    .select('id')
    .eq('stripe_customer_id', customerId)
    .single()

  return showroom?.id || null
}

// --- Credit System Handlers ---

async function handleCreditTopup(session: Stripe.Checkout.Session) {
  const showroomId = session.metadata?.showroom_id
  const amountCents = parseInt(session.metadata?.amount_cents || '0', 10)

  if (!showroomId || !amountCents) {
    console.error('[CREDIT_TOPUP] Missing metadata:', session.metadata)
    return
  }

  const { data, error } = await supabaseAdmin.rpc('add_showroom_credit', {
    p_showroom_id: showroomId,
    p_amount_cents: amountCents,
    p_type: 'top_up',
    p_notes: `Stripe top-up $${(amountCents / 100).toFixed(2)}`,
    p_stripe_session_id: session.id,
  })

  if (error) {
    console.error('[CREDIT_TOPUP] RPC error:', error)
    throw new Error(`Failed to add credits: ${error.message}`)
  }

  const result = data?.[0] || data
  console.log(`[CREDIT_TOPUP] Added $${(amountCents / 100).toFixed(2)} to showroom ${showroomId}. New balance: $${((result?.new_balance_cents || 0) / 100).toFixed(2)}`)
}

async function grantPlanBonus(showroomId: string, planSlug: string, frequency: 'one_time' | 'monthly') {
  const { data: bonus } = await supabaseAdmin
    .from('credit_plan_bonuses')
    .select('bonus_cents')
    .eq('subscription_plan', planSlug)
    .eq('frequency', frequency)
    .eq('is_active', true)
    .single()

  if (!bonus) return

  // For one_time: check if already granted
  if (frequency === 'one_time') {
    const { count } = await supabaseAdmin
      .from('showroom_credit_transactions')
      .select('*', { count: 'exact', head: true })
      .eq('showroom_id', showroomId)
      .eq('type', 'plan_bonus')
      .ilike('notes', `%${planSlug}%one-time%`)

    if ((count || 0) > 0) {
      console.log(`[PLAN_BONUS] One-time bonus already granted for showroom ${showroomId} plan ${planSlug}`)
      return
    }
  }

  const { error } = await supabaseAdmin.rpc('add_showroom_credit', {
    p_showroom_id: showroomId,
    p_amount_cents: bonus.bonus_cents,
    p_type: 'plan_bonus',
    p_notes: `${planSlug} plan ${frequency === 'one_time' ? 'one-time' : 'monthly'} bonus`,
  })

  if (error) {
    console.error(`[PLAN_BONUS] Failed to grant bonus for showroom ${showroomId}:`, error)
  } else {
    console.log(`[PLAN_BONUS] Granted $${(bonus.bonus_cents / 100).toFixed(2)} ${frequency} bonus to showroom ${showroomId} (${planSlug})`)
  }
}
