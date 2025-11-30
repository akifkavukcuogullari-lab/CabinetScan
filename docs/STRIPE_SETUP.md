# Stripe Integration Setup Guide

This guide explains how to configure Stripe for the Nextlyn Scan subscription billing system.

## Prerequisites

1. Create a Stripe account at https://stripe.com
2. Access to Supabase dashboard for setting secrets

## Step 1: Create Stripe Products and Prices

In the Stripe Dashboard:

1. Go to **Products** > **Add Product**
2. Create the following products:

### Basic Plan ($100/month)
- **Name**: Basic
- **Price**: $100.00 / month (recurring)
- **Price ID**: Copy this (starts with `price_`)
- Also create yearly price: $1,000.00 / year

### Pro Plan ($250/month)
- **Name**: Pro
- **Price**: $250.00 / month (recurring)
- **Price ID**: Copy this (starts with `price_`)
- Also create yearly price: $2,500.00 / year

## Step 2: Get API Keys

In Stripe Dashboard:

1. Go to **Developers** > **API keys**
2. Copy your **Secret key** (starts with `sk_test_` or `sk_live_`)
3. For webhooks, you'll create this in the next step

## Step 3: Create Webhook Endpoint

1. Go to **Developers** > **Webhooks**
2. Click **Add endpoint**
3. **Endpoint URL**: `https://wnyrnpeabhxdqvcpofmb.supabase.co/functions/v1/stripe-webhook`
4. Select events to listen to:
   - `checkout.session.completed`
   - `customer.subscription.created`
   - `customer.subscription.updated`
   - `customer.subscription.deleted`
   - `invoice.paid`
   - `invoice.payment_failed`
5. Click **Add endpoint**
6. Copy the **Signing secret** (starts with `whsec_`)

## Step 4: Configure Supabase Secrets

Run these commands to set secrets in Supabase:

```bash
# Navigate to project directory
cd /path/to/CabinetScan

# Set Stripe API key
supabase secrets set STRIPE_SECRET_KEY=sk_test_your_key_here

# Set Stripe webhook secret
supabase secrets set STRIPE_WEBHOOK_SECRET=whsec_your_secret_here

# Set price IDs
supabase secrets set STRIPE_PRICE_BASIC_MONTHLY=price_basic_monthly_id
supabase secrets set STRIPE_PRICE_BASIC_YEARLY=price_basic_yearly_id
supabase secrets set STRIPE_PRICE_PRO_MONTHLY=price_pro_monthly_id
supabase secrets set STRIPE_PRICE_PRO_YEARLY=price_pro_yearly_id

# Set dashboard URL
supabase secrets set DASHBOARD_URL=https://cabinet.nextlyn.ai
```

## Step 5: Update Database with Stripe Price IDs

Run this SQL in Supabase SQL Editor to update the subscription plans:

```sql
-- Update Basic plan
UPDATE subscription_plans
SET
  stripe_price_id_monthly = 'price_basic_monthly_id',
  stripe_price_id_yearly = 'price_basic_yearly_id',
  stripe_product_id = 'prod_basic_id'
WHERE slug = 'basic';

-- Update Pro plan
UPDATE subscription_plans
SET
  stripe_price_id_monthly = 'price_pro_monthly_id',
  stripe_price_id_yearly = 'price_pro_yearly_id',
  stripe_product_id = 'prod_pro_id'
WHERE slug = 'pro';
```

## Step 6: Deploy Edge Functions

```bash
supabase functions deploy create-checkout-session
supabase functions deploy stripe-webhook
supabase functions deploy create-portal-session
```

## Step 7: Configure Stripe Customer Portal

1. Go to **Settings** > **Billing** > **Customer portal**
2. Enable the following:
   - **Invoices**: Allow downloading invoices
   - **Subscriptions**: Allow customers to update subscriptions
   - **Payment methods**: Allow updating payment methods
   - **Cancel subscriptions**: Allow cancellation (with feedback)
3. Click **Save changes**

## Testing

### Test Mode
Use these test cards in test mode:
- **Success**: 4242 4242 4242 4242
- **Decline**: 4000 0000 0000 0002
- **3D Secure**: 4000 0025 0000 3155

### Test the Flow
1. Go to `/showroom/billing` in the dashboard
2. Click **Subscribe** on a plan
3. Complete checkout with a test card
4. Verify subscription is updated in the database

## Going Live

1. Switch to **Live mode** in Stripe dashboard
2. Create live products/prices (repeat Step 1)
3. Update secrets with live keys (repeat Step 4)
4. Create live webhook endpoint (repeat Step 3)
5. Update database with live price IDs (repeat Step 5)
6. Deploy edge functions again (repeat Step 6)

## Environment Variables Summary

| Variable | Description | Example |
|----------|-------------|---------|
| STRIPE_SECRET_KEY | Stripe API secret key | sk_live_xxx |
| STRIPE_WEBHOOK_SECRET | Webhook signing secret | whsec_xxx |
| STRIPE_PRICE_BASIC_MONTHLY | Basic plan monthly price ID | price_xxx |
| STRIPE_PRICE_BASIC_YEARLY | Basic plan yearly price ID | price_xxx |
| STRIPE_PRICE_PRO_MONTHLY | Pro plan monthly price ID | price_xxx |
| STRIPE_PRICE_PRO_YEARLY | Pro plan yearly price ID | price_xxx |
| DASHBOARD_URL | Dashboard URL for redirects | https://cabinet.nextlyn.ai |

## Troubleshooting

### Webhook Errors
- Check Supabase Edge Function logs
- Verify webhook secret is correct
- Ensure webhook endpoint is accessible

### Checkout Errors
- Check browser console for errors
- Verify price IDs are correct
- Check Stripe logs for API errors

### Subscription Not Updating
- Check webhook delivery in Stripe dashboard
- Verify webhook events are being received
- Check Supabase Edge Function logs
