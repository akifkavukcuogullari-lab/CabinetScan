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
    primary_color: string
    secondary_color: string
    accent_color: string
    background_color: string
    text_color: string
    welcome_message: string | null
    thank_you_message: string | null
    terms_url: string | null
    privacy_url: string | null
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
        subscription_plans (
          slug,
          has_video_capture,
          video_max_duration_seconds,
          video_max_size_mb,
          has_custom_branding,
          has_product_selection
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
    const isSubscriptionActive = ['trial', 'active'].includes(showroom.subscription_status)

    console.log(`[VIDEO CAPTURE] Showroom: ${showroom.name}`)
    console.log(`[VIDEO CAPTURE] Subscription status: ${showroom.subscription_status}`)
    console.log(`[VIDEO CAPTURE] Plan: ${plan?.slug}`)
    console.log(`[VIDEO CAPTURE] Plan has_video_capture: ${plan?.has_video_capture}`)
    console.log(`[VIDEO CAPTURE] Is subscription active: ${isSubscriptionActive}`)

    const videoCapture = plan?.has_video_capture && isSubscriptionActive
      ? {
          enabled: true,
          max_duration_seconds: plan.video_max_duration_seconds || 300,
          max_size_mb: plan.video_max_size_mb || 500,
        }
      : null

    console.log(`[VIDEO CAPTURE] Final videoCapture:`, videoCapture)

    // Check if custom branding (logo) is available for this plan
    const hasCustomBranding = plan?.has_custom_branding ?? false
    // Check if product selection is available for this plan (Starter = scan-only)
    const hasProductSelection = plan?.has_product_selection ?? false

    const config: ShowroomConfig = {
      id: showroom.id,
      name: showroom.name,
      showroom_code: showroom.showroom_code,
      branding: branding
        ? {
            // Only include logo/colors if plan has custom branding feature (Pro+)
            logo_url: hasCustomBranding ? branding.logo_url : null,
            logo_dark_url: hasCustomBranding ? branding.logo_dark_url : null,
            primary_color: hasCustomBranding ? branding.primary_color : '#2563EB',
            secondary_color: hasCustomBranding ? branding.secondary_color : '#1E40AF',
            accent_color: hasCustomBranding ? branding.accent_color : '#3B82F6',
            background_color: hasCustomBranding ? branding.background_color : '#FFFFFF',
            text_color: hasCustomBranding ? branding.text_color : '#1F2937',
            welcome_message: branding.welcome_message,
            thank_you_message: branding.thank_you_message,
            terms_url: branding.terms_url,
            privacy_url: branding.privacy_url,
          }
        : {
            logo_url: null,
            logo_dark_url: null,
            primary_color: '#2563EB',
            secondary_color: '#1E40AF',
            accent_color: '#3B82F6',
            background_color: '#FFFFFF',
            text_color: '#1F2937',
            welcome_message: null,
            thank_you_message: null,
            terms_url: null,
            privacy_url: null,
          },
      // Only include categories/products if plan has product selection (Pro+)
      categories: hasProductSelection ? categoriesWithProducts : [],
      // Only include addons if plan has product selection (Pro+)
      addons: hasProductSelection ? (addons || []).map((a: any) => ({
        id: a.id,
        question: a.question,
        description: a.description,
        unit: a.unit,
        price_per_unit: a.price_per_unit,
        image_url: a.image_url,
        display_order: a.display_order,
        use_color_coefficient: a.use_color_coefficient || false,
      })) : [],
      subscription: {
        status: showroom.subscription_status,
        plan: plan?.slug || null,
        video_capture: videoCapture,
      },
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
