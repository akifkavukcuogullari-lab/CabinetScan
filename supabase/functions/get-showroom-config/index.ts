import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { corsHeaders } from '../_shared/cors.ts'
import { supabaseAdmin } from '../_shared/supabase.ts'

interface ProductVariant {
  id: string
  name: string
  color_code: string | null
  price: number | null
  price_coefficient: number
  image_url: string | null
  thumbnail_url: string | null
  display_order: number
  is_default: boolean
}

interface Addon {
  id: string
  question: string
  description: string | null
  unit: string
  price_per_unit: number | null
  image_url: string | null
  display_order: number
  use_color_coefficient: boolean
  show_price_to_customer: boolean
}

interface Product {
  id: string
  name: string
  description: string | null
  price: number | null
  image_url: string | null
  thumbnail_url: string | null
  display_order: number
  is_featured: boolean
  specifications: Record<string, unknown>
  has_variants: boolean
  use_color_coefficient: boolean
  variants: ProductVariant[]
}

interface ShowroomConfig {
  id: string
  name: string
  showroom_code: string
  branding: {
    logo_url: string | null
    logo_dark_url: string | null
  }
  categories: Array<{
    id: string
    category_id: string
    name: string
    slug: string
    description: string | null
    pricing_unit: string
    icon_name: string | null
    display_order: number
    is_required: boolean
    show_price_to_customer: boolean
    products: Product[]
  }>
  addons: Addon[]
  subscription: {
    status: string
    plan: string | null
    video_capture: {
      enabled: boolean
      max_duration_seconds: number
      max_size_mb: number
    } | null
  }
  ai_chatbot: {
    enabled: boolean
    assistant_name: string
    assistant_avatar_url: string | null
  } | null
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const url = new URL(req.url)
    const showroomCode = url.searchParams.get('code')

    if (!showroomCode) {
      return new Response(
        JSON.stringify({ error: 'Showroom code is required' }),
        {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        }
      )
    }

    // Fetch showroom by code with subscription info
    const { data: showroom, error: showroomError } = await supabaseAdmin
      .from('showrooms')
      .select(`
        id,
        name,
        showroom_code,
        subscription_status,
        subscription_plan,
        trial_ends_at,
        ai_chatbot_enabled,
        ai_assistant_name,
        ai_assistant_avatar_url,
        addon_show_price_to_customer,
        subscription_plans (
          slug,
          has_video_capture,
          video_max_duration_seconds,
          video_max_size_mb,
          has_custom_branding,
          has_product_selection,
          has_ai_agent
        )
      `)
      .eq('showroom_code', showroomCode.toUpperCase())
      .eq('is_active', true)
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

    // Fetch branding
    const { data: branding } = await supabaseAdmin
      .from('showroom_branding')
      .select('*')
      .eq('showroom_id', showroom.id)
      .single()

    // Fetch enabled categories with products
    const { data: showroomCategories } = await supabaseAdmin
      .from('showroom_categories')
      .select(`
        id,
        category_id,
        display_order,
        custom_name,
        is_required,
        show_price_to_customer,
        categories (
          name,
          slug,
          description,
          pricing_unit,
          icon_name
        )
      `)
      .eq('showroom_id', showroom.id)
      .eq('is_enabled', true)
      .order('display_order')

    // Fetch products for this showroom
    const { data: products } = await supabaseAdmin
      .from('products')
      .select('*')
      .eq('showroom_id', showroom.id)
      .eq('is_active', true)
      .order('display_order')

    // Fetch enabled addons for this showroom
    const { data: addons } = await supabaseAdmin
      .from('showroom_addons')
      .select('id, question, description, unit, price_per_unit, image_url, display_order, use_color_coefficient')
      .eq('showroom_id', showroom.id)
      .eq('is_enabled', true)
      .order('display_order')

    // Fetch variants for products that have them
    const productIds = (products || []).map((p: any) => p.id)
    const { data: variants } = await supabaseAdmin
      .from('product_variants')
      .select('*')
      .in('product_id', productIds)
      .eq('is_active', true)
      .order('display_order')

    // Group variants by product_id
    const variantsByProduct: Record<string, ProductVariant[]> = {}
    for (const v of variants || []) {
      if (!variantsByProduct[v.product_id]) {
        variantsByProduct[v.product_id] = []
      }
      variantsByProduct[v.product_id].push({
        id: v.id,
        name: v.name,
        color_code: v.color_code,
        price: v.price,
        price_coefficient: v.price_coefficient || 1.0,
        image_url: v.image_url,
        thumbnail_url: v.thumbnail_url,
        display_order: v.display_order,
        is_default: v.is_default,
      })
    }

    // Build categories with their products
    const categoriesWithProducts = (showroomCategories || []).map((sc: any) => {
      const categoryProducts = (products || [])
        .filter((p: any) => p.category_id === sc.category_id)
        .map((p: any) => ({
          id: p.id,
          name: p.name,
          description: p.description,
          price: p.price,
          image_url: p.image_url,
          thumbnail_url: p.thumbnail_url,
          display_order: p.display_order,
          is_featured: p.is_featured,
          specifications: p.specifications,
          has_variants: p.has_variants || false,
          use_color_coefficient: p.use_color_coefficient || false,
          variants: variantsByProduct[p.id] || [],
        }))

      return {
        id: sc.id,
        category_id: sc.category_id,
        name: sc.custom_name || sc.categories.name,
        slug: sc.categories.slug,
        description: sc.categories.description,
        pricing_unit: sc.categories.pricing_unit,
        icon_name: sc.categories.icon_name,
        display_order: sc.display_order,
        is_required: sc.is_required,
        show_price_to_customer: sc.show_price_to_customer ?? true,
        products: categoryProducts,
      }
    })

    // Build video capture settings based on subscription
    const plan = showroom.subscription_plans as any

    // Check if trial has expired
    const isTrialExpired = showroom.subscription_status === 'trial' &&
      showroom.trial_ends_at &&
      new Date(showroom.trial_ends_at) < new Date()

    // Subscription is active if status is 'active' OR ('trial' and not expired)
    const isSubscriptionActive = showroom.subscription_status === 'active' ||
      (showroom.subscription_status === 'trial' && !isTrialExpired)

    // Trial users without a plan assigned get Pro features by default
    const isTrialWithProFeatures = showroom.subscription_status === 'trial' && !isTrialExpired && !plan

    console.log(`[VIDEO CAPTURE] Showroom: ${showroom.name}`)
    console.log(`[VIDEO CAPTURE] Subscription status: ${showroom.subscription_status}`)
    console.log(`[VIDEO CAPTURE] Plan: ${plan?.slug || (isTrialWithProFeatures ? 'pro (trial default)' : null)}`)
    console.log(`[VIDEO CAPTURE] Plan has_video_capture: ${plan?.has_video_capture ?? isTrialWithProFeatures}`)
    console.log(`[VIDEO CAPTURE] Is subscription active: ${isSubscriptionActive}`)

    // For trial users without a plan: grant Pro features (video capture enabled)
    const hasVideoCapture = plan?.has_video_capture ?? isTrialWithProFeatures
    const videoCapture = hasVideoCapture && isSubscriptionActive
      ? {
          enabled: true,
          max_duration_seconds: plan?.video_max_duration_seconds || 300,
          max_size_mb: plan?.video_max_size_mb || 500,
        }
      : null

    console.log(`[VIDEO CAPTURE] Final videoCapture:`, videoCapture)

    // Check if custom branding (logo) is available for this plan
    // Trial users without a plan get Pro features (custom branding = true)
    const hasCustomBranding = plan?.has_custom_branding ?? isTrialWithProFeatures
    // Check if product selection is available for this plan (Starter = scan-only)
    // Trial users without a plan get Pro features (product selection = true)
    const hasProductSelection = plan?.has_product_selection ?? isTrialWithProFeatures
    // Check if AI agent is available (Business+ plans only)
    // First check subscription_plans table, then fallback to subscription_plan TEXT field
    const hasAiAgent = plan?.has_ai_agent ??
      ['business', 'enterprise'].includes((showroom as any).subscription_plan || '')

    // Default CabinetScan branding for Starter plan
    const CABINETSCAN_LOGO = 'https://wnyrnpeabhxdqvcpofmb.supabase.co/storage/v1/object/public/logos/cabinetscan-logo.png'
    const CABINETSCAN_LOGO_DARK = 'https://wnyrnpeabhxdqvcpofmb.supabase.co/storage/v1/object/public/logos/cabinetscan-logo-dark.png'

    const config: ShowroomConfig = {
      id: showroom.id,
      // Show "CabinetScan" for Starter plan, actual showroom name for Pro+
      name: hasCustomBranding ? showroom.name : 'CabinetScan',
      showroom_code: showroom.showroom_code,
      branding: {
        // Use CabinetScan logo for Starter, custom logo for Pro+
        logo_url: hasCustomBranding && branding?.logo_url ? branding.logo_url : CABINETSCAN_LOGO,
        logo_dark_url: hasCustomBranding && branding?.logo_dark_url ? branding.logo_dark_url : CABINETSCAN_LOGO_DARK,
      },
      // Only include categories/products if plan has product selection (Pro+)
      categories: hasProductSelection ? categoriesWithProducts : [],
      // Only include addons if plan has product selection (Pro+)
      // show_price_to_customer is now a showroom-level setting (applies to all addons)
      addons: hasProductSelection ? (addons || []).map((a: any) => ({
        id: a.id,
        question: a.question,
        description: a.description,
        unit: a.unit,
        price_per_unit: a.price_per_unit,
        image_url: a.image_url,
        display_order: a.display_order,
        use_color_coefficient: a.use_color_coefficient || false,
        show_price_to_customer: showroom.addon_show_price_to_customer ?? false,
      })) : [],
      subscription: {
        status: showroom.subscription_status,
        // Trial users without a plan get Pro features by default
        plan: plan?.slug || (isTrialWithProFeatures ? 'pro' : null),
        video_capture: videoCapture,
      },
      // AI chatbot config - only available for Business+ plans with it enabled
      ai_chatbot: (hasAiAgent && showroom.ai_chatbot_enabled && isSubscriptionActive)
        ? {
            enabled: true,
            assistant_name: showroom.ai_assistant_name || 'Design Assistant',
            assistant_avatar_url: showroom.ai_assistant_avatar_url,
          }
        : null,
    }

    return new Response(JSON.stringify(config), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  } catch (error) {
    console.error('Error fetching showroom config:', error)
    return new Response(
      JSON.stringify({ error: 'Internal server error' }),
      {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      }
    )
  }
})
