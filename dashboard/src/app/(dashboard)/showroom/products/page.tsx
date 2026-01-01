import { createClient } from '@/lib/supabase/server'
import { Card, CardContent } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { Plus, Package, Sparkles } from 'lucide-react'
import Link from 'next/link'
import { redirect } from 'next/navigation'
import Image from 'next/image'
import { CustomAddons } from '@/components/products/CustomAddons'
import { CategoryPriceToggle } from '@/components/products/CategoryPriceToggle'

export default async function ProductsPage({
  searchParams,
}: {
  searchParams: Promise<{ category?: string }>
}) {
  const { category: selectedCategory } = await searchParams
  const supabase = await createClient()

  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  // Get the user's showroom
  const { data: showroomUser } = await supabase
    .from('showroom_users')
    .select('showroom_id')
    .eq('user_id', user.id)
    .single()

  if (!showroomUser) redirect('/login')

  // Get categories with products for this showroom
  const { data: showroomCategories } = await supabase
    .from('showroom_categories')
    .select(`
      id,
      category_id,
      custom_name,
      is_enabled,
      show_price_to_customer,
      categories (
        name,
        slug
      )
    `)
    .eq('showroom_id', showroomUser.showroom_id)
    .eq('is_enabled', true)
    .order('display_order')

  const { data: products } = await supabase
    .from('products')
    .select('*')
    .eq('showroom_id', showroomUser.showroom_id)
    .order('display_order')

  // Get all master categories for the tabs
  const { data: categories } = await supabase
    .from('categories')
    .select('*')
    .eq('is_active', true)
    .order('display_order')

  const productsByCategory = categories?.reduce((acc: Record<string, any[]>, category: any) => {
    acc[category.id] = (products || []).filter((p: any) => p.category_id === category.id)
    return acc
  }, {} as Record<string, any[]>)

  const enabledCategoryIds = new Set(showroomCategories?.map((sc: any) => sc.category_id) || [])

  // Map category_id to showroom_category data for toggle
  const showroomCategoryMap = (showroomCategories || []).reduce((acc: Record<string, any>, sc: any) => {
    acc[sc.category_id] = sc
    return acc
  }, {} as Record<string, any>)

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold">Products</h1>
          <p className="text-gray-500">Manage your showroom products by category</p>
        </div>
        <Link href="/showroom/products/new">
          <Button>
            <Plus className="h-4 w-4 mr-2" />
            Add Product
          </Button>
        </Link>
      </div>

      {categories && categories.length > 0 ? (
        <Tabs defaultValue={selectedCategory || categories[0]?.id} className="space-y-4">
          <TabsList className="flex-wrap h-auto gap-1">
            {categories.map((category: any) => (
              <TabsTrigger
                key={category.id}
                value={category.id}
              >
                {category.name}
              </TabsTrigger>
            ))}
            <TabsTrigger value="custom-addons">
              <Sparkles className="h-4 w-4 mr-1.5" />
              Custom Addon Items
            </TabsTrigger>
          </TabsList>

          {categories.map((category: any) => (
            <TabsContent key={category.id} value={category.id}>
              {!enabledCategoryIds.has(category.id) && (
                <div className="mb-4 p-3 bg-yellow-50 border border-yellow-200 rounded-md">
                  <p className="text-sm text-yellow-800">
                    This category is not enabled for your showroom. Enable it in{' '}
                    <Link href="/showroom/settings" className="underline">
                      Settings
                    </Link>{' '}
                    to make products visible to customers.
                  </p>
                </div>
              )}

              {/* Category-level price toggle */}
              {showroomCategoryMap[category.id] && (
                <div className="mb-4 p-3 bg-gray-50 border border-gray-200 rounded-md flex items-center justify-between">
                  <div>
                    <p className="text-sm font-medium text-gray-700">Price Visibility</p>
                    <p className="text-xs text-gray-500">Control whether prices are shown for all {category.name} products</p>
                  </div>
                  <CategoryPriceToggle
                    showroomCategoryId={showroomCategoryMap[category.id].id}
                    categoryName={category.name}
                    initialValue={showroomCategoryMap[category.id].show_price_to_customer ?? true}
                  />
                </div>
              )}

              {productsByCategory?.[category.id]?.length > 0 ? (
                <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
                  {productsByCategory[category.id]?.map((product: any) => (
                    <Card key={product.id} className="overflow-hidden">
                      <div className="aspect-square relative bg-gray-100">
                        {product.image_url ? (
                          <Image
                            src={product.image_url}
                            alt={product.name}
                            fill
                            className="object-cover"
                          />
                        ) : (
                          <div className="flex items-center justify-center h-full">
                            <Package className="h-12 w-12 text-gray-300" />
                          </div>
                        )}
                        {product.is_featured && (
                          <Badge className="absolute top-2 right-2 bg-yellow-500">
                            Featured
                          </Badge>
                        )}
                      </div>
                      <CardContent className="p-4">
                        <div className="flex items-start justify-between">
                          <div>
                            <h3 className="font-medium">{product.name}</h3>
                            {product.price !== null && (
                              <p className="text-sm text-gray-500">
                                ${product.price.toFixed(2)}
                              </p>
                            )}
                          </div>
                          <Badge variant={product.is_active ? 'default' : 'secondary'}>
                            {product.is_active ? 'Active' : 'Inactive'}
                          </Badge>
                        </div>
                        <Link href={`/showroom/products/${product.id}`}>
                          <Button variant="ghost" size="sm" className="mt-2 w-full">
                            Edit
                          </Button>
                        </Link>
                      </CardContent>
                    </Card>
                  ))}
                </div>
              ) : (
                <Card>
                  <CardContent className="py-10 text-center">
                    <Package className="h-12 w-12 mx-auto text-gray-400 mb-4" />
                    <h3 className="text-lg font-medium mb-2">
                      No products in {category.name}
                    </h3>
                    <p className="text-gray-500 mb-4">
                      Add products to this category to show them to customers
                    </p>
                    <Link href={`/showroom/products/new?category=${category.id}`}>
                      <Button>
                        <Plus className="h-4 w-4 mr-2" />
                        Add Product
                      </Button>
                    </Link>
                  </CardContent>
                </Card>
              )}
            </TabsContent>
          ))}

          {/* Custom Addon Items Tab */}
          <TabsContent value="custom-addons">
            <CustomAddons showroomId={showroomUser.showroom_id} />
          </TabsContent>
        </Tabs>
      ) : (
        <Card>
          <CardContent className="py-10 text-center">
            <Package className="h-12 w-12 mx-auto text-gray-400 mb-4" />
            <h3 className="text-lg font-medium mb-2">No categories available</h3>
            <p className="text-gray-500">
              Contact support to set up product categories
            </p>
          </CardContent>
        </Card>
      )}
    </div>
  )
}
