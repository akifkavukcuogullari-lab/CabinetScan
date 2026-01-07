// Stripe helper for Edge Functions
// NOTE: Add STRIPE_SECRET_KEY and STRIPE_WEBHOOK_SECRET to Supabase secrets

import Stripe from 'https://esm.sh/stripe@14.12.0?target=deno'

const stripeSecretKey = Deno.env.get('STRIPE_SECRET_KEY')
const stripeWebhookSecret = Deno.env.get('STRIPE_WEBHOOK_SECRET')

// Stripe client - will return null if not configured
export const stripe = stripeSecretKey
  ? new Stripe(stripeSecretKey, {
      apiVersion: '2023-10-16',
      httpClient: Stripe.createFetchHttpClient(),
    })
  : null

export const webhookSecret = stripeWebhookSecret

// Check if Stripe is configured
export function isStripeConfigured(): boolean {
  return !!stripeSecretKey && stripeSecretKey !== 'sk_test_PLACEHOLDER'
}

// Verify webhook signature
export async function verifyWebhookSignature(
  body: string,
  signature: string
): Promise<Stripe.Event | null> {
  if (!stripe || !webhookSecret) {
    console.error('Stripe not configured')
    return null
  }

  try {
    return await stripe.webhooks.constructEventAsync(
      body,
      signature,
      webhookSecret
    )
  } catch (err) {
    console.error('Webhook signature verification failed:', err)
    return null
  }
}

// Price IDs - to be updated when Stripe is configured
export const PRICE_IDS = {
  // Starter: $49/mo, $470/yr
  starter_monthly: Deno.env.get('STRIPE_PRICE_STARTER_MONTHLY') || '',
  starter_yearly: Deno.env.get('STRIPE_PRICE_STARTER_YEARLY') || '',
  // Pro: $149/mo, $1430/yr
  pro_monthly: Deno.env.get('STRIPE_PRICE_PRO_MONTHLY') || '',
  pro_yearly: Deno.env.get('STRIPE_PRICE_PRO_YEARLY') || '',
  // Business: $249/mo, $2390/yr
  business_monthly: Deno.env.get('STRIPE_PRICE_BUSINESS_MONTHLY') || '',
  business_yearly: Deno.env.get('STRIPE_PRICE_BUSINESS_YEARLY') || '',
}

// Dashboard URLs
export const DASHBOARD_URL = Deno.env.get('DASHBOARD_URL') || 'https://cabinet.nextlyn.ai'
