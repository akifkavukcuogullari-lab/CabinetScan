'use client'

import { useState, useEffect, use } from 'react'
import { useRouter } from 'next/navigation'
import Link from 'next/link'
import { createClient } from '@/lib/supabase/client'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Textarea } from '@/components/ui/textarea'
import { Switch } from '@/components/ui/switch'
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from '@/components/ui/card'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
  AlertDialogTrigger,
} from '@/components/ui/alert-dialog'
import { ArrowLeft, Loader2, Upload, X, Trash2, Plus, Palette, GripVertical } from 'lucide-react'
import { Badge } from '@/components/ui/badge'

interface Category {
  id: string
  name: string
  slug: string
  pricing_unit: string
}

interface ProductVariant {
  id: string
  product_id: string
  name: string
  color_code: string | null
  price: number | null
  image_url: string | null
  display_order: number
  is_active: boolean
  is_default: boolean
}

interface Product {
  id: string
  showroom_id: string
  category_id: string
  name: string
  description: string | null
  sku: string | null
  price: number | null
  is_active: boolean
  is_featured: boolean
  has_variants: boolean
  image_url: string | null
}

export default function EditProductPage({
  params,
}: {
  params: Promise<{ id: string }>
}) {
  const { id } = use(params)
  const router = useRouter()
  const supabase = createClient()

  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [deleting, setDeleting] = useState(false)
  const [uploading, setUploading] = useState(false)
  const [showroomId, setShowroomId] = useState<string | null>(null)
  const [categories, setCategories] = useState<Category[]>([])
  const [error, setError] = useState<string | null>(null)
  const [product, setProduct] = useState<Product | null>(null)
  const [variants, setVariants] = useState<ProductVariant[]>([])
  const [editingVariant, setEditingVariant] = useState<ProductVariant | null>(null)
  const [showVariantForm, setShowVariantForm] = useState(false)
  const [variantUploading, setVariantUploading] = useState(false)

  const [formData, setFormData] = useState({
    name: '',
    description: '',
    sku: '',
    price: '',
    category_id: '',
    is_active: true,
    is_featured: false,
    has_variants: false,
    image_url: '',
  })

  const [variantForm, setVariantForm] = useState({
    name: '',
    color_code: '',
    price: '',
    image_url: '',
    is_default: false,
  })

  useEffect(() => {
    async function loadData() {
      const {
        data: { user },
      } = await supabase.auth.getUser()
      if (!user) {
        router.push('/login')
        return
      }

      const { data: showroomUser } = await supabase
        .from('showroom_users')
        .select('showroom_id')
        .eq('user_id', user.id)
        .single()

      if (!showroomUser) {
        router.push('/login')
        return
      }

      setShowroomId(showroomUser.showroom_id)

      // Load product
      const { data: productData, error: productError } = await supabase
        .from('products')
        .select('*')
        .eq('id', id)
        .eq('showroom_id', showroomUser.showroom_id)
        .single()

      if (productError || !productData) {
        router.push('/showroom/products')
        return
      }

      setProduct(productData)
      setFormData({
        name: productData.name,
        description: productData.description || '',
        sku: productData.sku || '',
        price: productData.price?.toString() || '',
        category_id: productData.category_id,
        is_active: productData.is_active,
        is_featured: productData.is_featured,
        has_variants: productData.has_variants || false,
        image_url: productData.image_url || '',
      })

      // Load variants
      const { data: variantsData } = await supabase
        .from('product_variants')
        .select('*')
        .eq('product_id', id)
        .order('display_order')

      if (variantsData) {
        setVariants(variantsData)
      }

      // Load categories
      const { data: categoriesData } = await supabase
        .from('categories')
        .select('id, name, slug, pricing_unit')
        .eq('is_active', true)
        .order('display_order')

      if (categoriesData) {
        setCategories(categoriesData)
      }

      setLoading(false)
    }

    loadData()
  }, [supabase, router, id])

  const handleImageUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    if (!file || !showroomId) return

    setUploading(true)
    setError(null)

    try {
      const fileExt = file.name.split('.').pop()
      const fileName = `${showroomId}/${Date.now()}.${fileExt}`

      const { error: uploadError } = await supabase.storage
        .from('products')
        .upload(fileName, file)

      if (uploadError) throw uploadError

      const {
        data: { publicUrl },
      } = supabase.storage.from('products').getPublicUrl(fileName)

      setFormData((prev) => ({ ...prev, image_url: publicUrl }))
    } catch (err) {
      console.error('Error uploading image:', err)
      setError('Failed to upload image. Please try again.')
    } finally {
      setUploading(false)
    }
  }

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!product) return

    setSaving(true)
    setError(null)

    try {
      const { error: updateError } = await supabase
        .from('products')
        .update({
          category_id: formData.category_id,
          name: formData.name,
          description: formData.description || null,
          sku: formData.sku || null,
          price: formData.price ? parseFloat(formData.price) : null,
          is_active: formData.is_active,
          is_featured: formData.is_featured,
          has_variants: formData.has_variants,
          image_url: formData.image_url || null,
        })
        .eq('id', product.id)

      if (updateError) throw updateError

      router.push('/showroom/products')
    } catch (err) {
      console.error('Error updating product:', err)
      setError('Failed to update product. Please try again.')
    } finally {
      setSaving(false)
    }
  }

  const handleDelete = async () => {
    if (!product) return

    setDeleting(true)
    setError(null)

    try {
      const { error: deleteError } = await supabase
        .from('products')
        .delete()
        .eq('id', product.id)

      if (deleteError) throw deleteError

      router.push('/showroom/products')
    } catch (err) {
      console.error('Error deleting product:', err)
      setError('Failed to delete product. Please try again.')
    } finally {
      setDeleting(false)
    }
  }

  const selectedCategory = categories.find((c) => c.id === formData.category_id)
  const isCabinetModel = selectedCategory?.slug === 'cabinet-model'

  // Variant management functions
  const resetVariantForm = () => {
    setVariantForm({
      name: '',
      color_code: '',
      price: '',
      image_url: '',
      is_default: false,
    })
    setEditingVariant(null)
    setShowVariantForm(false)
  }

  const handleVariantImageUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    if (!file || !showroomId) return

    setVariantUploading(true)

    try {
      const fileExt = file.name.split('.').pop()
      const fileName = `${showroomId}/variants/${Date.now()}.${fileExt}`

      const { error: uploadError } = await supabase.storage
        .from('products')
        .upload(fileName, file)

      if (uploadError) throw uploadError

      const {
        data: { publicUrl },
      } = supabase.storage.from('products').getPublicUrl(fileName)

      setVariantForm((prev) => ({ ...prev, image_url: publicUrl }))
    } catch (err) {
      console.error('Error uploading variant image:', err)
      setError('Failed to upload variant image.')
    } finally {
      setVariantUploading(false)
    }
  }

  const handleSaveVariant = async () => {
    if (!product || !variantForm.name) return

    try {
      if (editingVariant) {
        // Update existing variant
        const { error } = await supabase
          .from('product_variants')
          .update({
            name: variantForm.name,
            color_code: variantForm.color_code || null,
            price: variantForm.price ? parseFloat(variantForm.price) : null,
            image_url: variantForm.image_url || null,
            is_default: variantForm.is_default,
          })
          .eq('id', editingVariant.id)

        if (error) throw error

        setVariants((prev) =>
          prev.map((v) =>
            v.id === editingVariant.id
              ? {
                  ...v,
                  name: variantForm.name,
                  color_code: variantForm.color_code || null,
                  price: variantForm.price ? parseFloat(variantForm.price) : null,
                  image_url: variantForm.image_url || null,
                  is_default: variantForm.is_default,
                }
              : variantForm.is_default ? { ...v, is_default: false } : v
          )
        )
      } else {
        // Create new variant
        const { data, error } = await supabase
          .from('product_variants')
          .insert({
            product_id: product.id,
            name: variantForm.name,
            color_code: variantForm.color_code || null,
            price: variantForm.price ? parseFloat(variantForm.price) : null,
            image_url: variantForm.image_url || null,
            is_default: variantForm.is_default,
            display_order: variants.length,
          })
          .select()
          .single()

        if (error) throw error

        // If new variant is default, unset others
        if (variantForm.is_default) {
          setVariants((prev) => [...prev.map((v) => ({ ...v, is_default: false })), data])
        } else {
          setVariants((prev) => [...prev, data])
        }
      }

      resetVariantForm()
    } catch (err) {
      console.error('Error saving variant:', err)
      setError('Failed to save variant.')
    }
  }

  const handleEditVariant = (variant: ProductVariant) => {
    setEditingVariant(variant)
    setVariantForm({
      name: variant.name,
      color_code: variant.color_code || '',
      price: variant.price?.toString() || '',
      image_url: variant.image_url || '',
      is_default: variant.is_default,
    })
    setShowVariantForm(true)
  }

  const handleDeleteVariant = async (variantId: string) => {
    try {
      const { error } = await supabase.from('product_variants').delete().eq('id', variantId)

      if (error) throw error

      setVariants((prev) => prev.filter((v) => v.id !== variantId))
    } catch (err) {
      console.error('Error deleting variant:', err)
      setError('Failed to delete variant.')
    }
  }

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <Loader2 className="h-8 w-8 animate-spin text-gray-400" />
      </div>
    )
  }

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-4">
          <Link href="/showroom/products">
            <Button variant="ghost" size="icon">
              <ArrowLeft className="h-5 w-5" />
            </Button>
          </Link>
          <div>
            <h1 className="text-2xl font-bold">Edit Product</h1>
            <p className="text-gray-500">Update product details</p>
          </div>
        </div>

        <AlertDialog>
          <AlertDialogTrigger asChild>
            <Button variant="destructive" size="sm">
              <Trash2 className="h-4 w-4 mr-2" />
              Delete
            </Button>
          </AlertDialogTrigger>
          <AlertDialogContent>
            <AlertDialogHeader>
              <AlertDialogTitle>Delete Product</AlertDialogTitle>
              <AlertDialogDescription>
                Are you sure you want to delete this product? This action cannot be
                undone.
              </AlertDialogDescription>
            </AlertDialogHeader>
            <AlertDialogFooter>
              <AlertDialogCancel>Cancel</AlertDialogCancel>
              <AlertDialogAction
                onClick={handleDelete}
                className="bg-red-600 hover:bg-red-700"
              >
                {deleting ? (
                  <>
                    <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                    Deleting...
                  </>
                ) : (
                  'Delete'
                )}
              </AlertDialogAction>
            </AlertDialogFooter>
          </AlertDialogContent>
        </AlertDialog>
      </div>

      <form onSubmit={handleSubmit}>
        <div className="grid gap-6 lg:grid-cols-3">
          {/* Main Info */}
          <div className="lg:col-span-2 space-y-6">
            <Card>
              <CardHeader>
                <CardTitle>Product Information</CardTitle>
                <CardDescription>Basic details about your product</CardDescription>
              </CardHeader>
              <CardContent className="space-y-4">
                {error && (
                  <div className="p-3 text-sm text-red-600 bg-red-50 rounded-md">
                    {error}
                  </div>
                )}

                <div className="space-y-2">
                  <Label htmlFor="name">Product Name *</Label>
                  <Input
                    id="name"
                    value={formData.name}
                    onChange={(e) =>
                      setFormData((prev) => ({ ...prev, name: e.target.value }))
                    }
                    placeholder="e.g., Shaker White Cabinet"
                    required
                  />
                </div>

                <div className="space-y-2">
                  <Label htmlFor="description">Description</Label>
                  <Textarea
                    id="description"
                    value={formData.description}
                    onChange={(e) =>
                      setFormData((prev) => ({ ...prev, description: e.target.value }))
                    }
                    placeholder="Describe your product..."
                    rows={4}
                  />
                </div>

                <div className="grid grid-cols-2 gap-4">
                  <div className="space-y-2">
                    <Label htmlFor="category">Category *</Label>
                    <Select
                      value={formData.category_id}
                      onValueChange={(value) =>
                        setFormData((prev) => ({ ...prev, category_id: value }))
                      }
                    >
                      <SelectTrigger>
                        <SelectValue placeholder="Select category" />
                      </SelectTrigger>
                      <SelectContent>
                        {categories.map((category) => (
                          <SelectItem key={category.id} value={category.id}>
                            {category.name}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  </div>

                  <div className="space-y-2">
                    <Label htmlFor="sku">SKU</Label>
                    <Input
                      id="sku"
                      value={formData.sku}
                      onChange={(e) =>
                        setFormData((prev) => ({ ...prev, sku: e.target.value }))
                      }
                      placeholder="e.g., CAB-001"
                    />
                  </div>
                </div>

                <div className="space-y-2">
                  <Label htmlFor="price">
                    Price{' '}
                    {selectedCategory && (
                      <span className="text-gray-500 font-normal">
                        ({selectedCategory.pricing_unit.replace('_', ' ')})
                      </span>
                    )}
                  </Label>
                  <div className="relative">
                    <span className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-500">
                      $
                    </span>
                    <Input
                      id="price"
                      type="number"
                      step="0.01"
                      min="0"
                      value={formData.price}
                      onChange={(e) =>
                        setFormData((prev) => ({ ...prev, price: e.target.value }))
                      }
                      placeholder="0.00"
                      className="pl-7"
                    />
                  </div>
                  <p className="text-xs text-gray-500">
                    Leave empty if price is quote-based
                  </p>
                </div>
              </CardContent>
            </Card>

            <Card>
              <CardHeader>
                <CardTitle>Product Image</CardTitle>
                <CardDescription>Upload an image for your product</CardDescription>
              </CardHeader>
              <CardContent>
                {formData.image_url ? (
                  <div className="relative aspect-square max-w-xs rounded-lg overflow-hidden bg-gray-100">
                    <img
                      src={formData.image_url}
                      alt="Product"
                      className="w-full h-full object-cover"
                    />
                    <Button
                      type="button"
                      variant="destructive"
                      size="icon"
                      className="absolute top-2 right-2"
                      onClick={() =>
                        setFormData((prev) => ({ ...prev, image_url: '' }))
                      }
                    >
                      <X className="h-4 w-4" />
                    </Button>
                  </div>
                ) : (
                  <label className="flex flex-col items-center justify-center w-full h-48 border-2 border-dashed border-gray-300 rounded-lg cursor-pointer hover:bg-gray-50 transition-colors">
                    <div className="flex flex-col items-center justify-center pt-5 pb-6">
                      {uploading ? (
                        <Loader2 className="h-8 w-8 animate-spin text-gray-400 mb-2" />
                      ) : (
                        <Upload className="h-8 w-8 text-gray-400 mb-2" />
                      )}
                      <p className="text-sm text-gray-500">
                        {uploading ? 'Uploading...' : 'Click to upload image'}
                      </p>
                      <p className="text-xs text-gray-400 mt-1">
                        PNG, JPG up to 5MB
                      </p>
                    </div>
                    <input
                      type="file"
                      className="hidden"
                      accept="image/*"
                      onChange={handleImageUpload}
                      disabled={uploading}
                    />
                  </label>
                )}
              </CardContent>
            </Card>

            {/* Color Variants - Only show for Cabinet Model category */}
            {isCabinetModel && (
              <Card>
                <CardHeader>
                  <div className="flex items-center justify-between">
                    <div>
                      <CardTitle className="flex items-center gap-2">
                        <Palette className="h-5 w-5" />
                        Color Variants
                      </CardTitle>
                      <CardDescription>
                        Add available colors for this cabinet model
                      </CardDescription>
                    </div>
                    <div className="flex items-center gap-2">
                      <Switch
                        id="has_variants"
                        checked={formData.has_variants}
                        onCheckedChange={(checked) =>
                          setFormData((prev) => ({ ...prev, has_variants: checked }))
                        }
                      />
                      <Label htmlFor="has_variants" className="text-sm">
                        Enable
                      </Label>
                    </div>
                  </div>
                </CardHeader>
                {formData.has_variants && (
                  <CardContent className="space-y-4">
                    {/* Existing variants */}
                    {variants.length > 0 && (
                      <div className="space-y-2">
                        {variants.map((variant) => (
                          <div
                            key={variant.id}
                            className="flex items-center gap-3 p-3 border rounded-lg hover:bg-gray-50"
                          >
                            <GripVertical className="h-4 w-4 text-gray-400 cursor-move" />
                            {variant.color_code ? (
                              <div
                                className="w-8 h-8 rounded border"
                                style={{ backgroundColor: variant.color_code }}
                              />
                            ) : variant.image_url ? (
                              <img
                                src={variant.image_url}
                                alt={variant.name}
                                className="w-8 h-8 rounded object-cover"
                              />
                            ) : (
                              <div className="w-8 h-8 rounded bg-gray-100 flex items-center justify-center">
                                <Palette className="h-4 w-4 text-gray-400" />
                              </div>
                            )}
                            <div className="flex-1 min-w-0">
                              <div className="flex items-center gap-2">
                                <span className="font-medium truncate">{variant.name}</span>
                                {variant.is_default && (
                                  <Badge variant="secondary" className="text-xs">
                                    Default
                                  </Badge>
                                )}
                              </div>
                              {variant.price && (
                                <span className="text-sm text-gray-500">
                                  ${variant.price.toFixed(2)}
                                </span>
                              )}
                            </div>
                            <Button
                              type="button"
                              variant="ghost"
                              size="sm"
                              onClick={() => handleEditVariant(variant)}
                            >
                              Edit
                            </Button>
                            <AlertDialog>
                              <AlertDialogTrigger asChild>
                                <Button type="button" variant="ghost" size="icon">
                                  <Trash2 className="h-4 w-4 text-red-500" />
                                </Button>
                              </AlertDialogTrigger>
                              <AlertDialogContent>
                                <AlertDialogHeader>
                                  <AlertDialogTitle>Delete Color Variant</AlertDialogTitle>
                                  <AlertDialogDescription>
                                    Are you sure you want to delete &quot;{variant.name}&quot;?
                                  </AlertDialogDescription>
                                </AlertDialogHeader>
                                <AlertDialogFooter>
                                  <AlertDialogCancel>Cancel</AlertDialogCancel>
                                  <AlertDialogAction
                                    onClick={() => handleDeleteVariant(variant.id)}
                                    className="bg-red-600 hover:bg-red-700"
                                  >
                                    Delete
                                  </AlertDialogAction>
                                </AlertDialogFooter>
                              </AlertDialogContent>
                            </AlertDialog>
                          </div>
                        ))}
                      </div>
                    )}

                    {/* Add/Edit variant form */}
                    {showVariantForm ? (
                      <div className="border rounded-lg p-4 space-y-4 bg-gray-50">
                        <h4 className="font-medium">
                          {editingVariant ? 'Edit Color' : 'Add New Color'}
                        </h4>
                        <div className="grid grid-cols-2 gap-4">
                          <div className="space-y-2">
                            <Label>Color Name *</Label>
                            <Input
                              value={variantForm.name}
                              onChange={(e) =>
                                setVariantForm((prev) => ({ ...prev, name: e.target.value }))
                              }
                              placeholder="e.g., White, Navy Blue"
                            />
                          </div>
                          <div className="space-y-2">
                            <Label>Color Code</Label>
                            <div className="flex gap-2">
                              <Input
                                type="color"
                                value={variantForm.color_code || '#ffffff'}
                                onChange={(e) =>
                                  setVariantForm((prev) => ({
                                    ...prev,
                                    color_code: e.target.value,
                                  }))
                                }
                                className="w-12 h-10 p-1"
                              />
                              <Input
                                value={variantForm.color_code}
                                onChange={(e) =>
                                  setVariantForm((prev) => ({
                                    ...prev,
                                    color_code: e.target.value,
                                  }))
                                }
                                placeholder="#FFFFFF"
                              />
                            </div>
                          </div>
                        </div>
                        <div className="grid grid-cols-2 gap-4">
                          <div className="space-y-2">
                            <Label>Price</Label>
                            <div className="relative">
                              <span className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-500">
                                $
                              </span>
                              <Input
                                type="number"
                                step="0.01"
                                min="0"
                                value={variantForm.price}
                                onChange={(e) =>
                                  setVariantForm((prev) => ({ ...prev, price: e.target.value }))
                                }
                                placeholder="0.00"
                                className="pl-7"
                              />
                            </div>
                          </div>
                          <div className="space-y-2">
                            <Label>Image (optional)</Label>
                            {variantForm.image_url ? (
                              <div className="flex items-center gap-2">
                                <img
                                  src={variantForm.image_url}
                                  alt="Variant"
                                  className="w-10 h-10 rounded object-cover"
                                />
                                <Button
                                  type="button"
                                  variant="ghost"
                                  size="sm"
                                  onClick={() =>
                                    setVariantForm((prev) => ({ ...prev, image_url: '' }))
                                  }
                                >
                                  <X className="h-4 w-4" />
                                </Button>
                              </div>
                            ) : (
                              <label className="flex items-center gap-2 cursor-pointer">
                                <Button type="button" variant="outline" size="sm" asChild>
                                  <span>
                                    {variantUploading ? (
                                      <Loader2 className="h-4 w-4 animate-spin" />
                                    ) : (
                                      <Upload className="h-4 w-4" />
                                    )}
                                  </span>
                                </Button>
                                <input
                                  type="file"
                                  className="hidden"
                                  accept="image/*"
                                  onChange={handleVariantImageUpload}
                                  disabled={variantUploading}
                                />
                              </label>
                            )}
                          </div>
                        </div>
                        <div className="flex items-center gap-2">
                          <Switch
                            id="variant_is_default"
                            checked={variantForm.is_default}
                            onCheckedChange={(checked) =>
                              setVariantForm((prev) => ({ ...prev, is_default: checked }))
                            }
                          />
                          <Label htmlFor="variant_is_default">Default color</Label>
                        </div>
                        <div className="flex gap-2">
                          <Button
                            type="button"
                            onClick={handleSaveVariant}
                            disabled={!variantForm.name}
                          >
                            {editingVariant ? 'Update' : 'Add'} Color
                          </Button>
                          <Button type="button" variant="outline" onClick={resetVariantForm}>
                            Cancel
                          </Button>
                        </div>
                      </div>
                    ) : (
                      <Button
                        type="button"
                        variant="outline"
                        className="w-full"
                        onClick={() => setShowVariantForm(true)}
                      >
                        <Plus className="h-4 w-4 mr-2" />
                        Add Color Variant
                      </Button>
                    )}

                    {variants.length === 0 && !showVariantForm && (
                      <p className="text-sm text-gray-500 text-center py-4">
                        No color variants added yet. Add colors that customers can choose from.
                      </p>
                    )}
                  </CardContent>
                )}
              </Card>
            )}
          </div>

          {/* Sidebar */}
          <div className="space-y-6">
            <Card>
              <CardHeader>
                <CardTitle>Status</CardTitle>
              </CardHeader>
              <CardContent className="space-y-4">
                <div className="flex items-center justify-between">
                  <div>
                    <Label htmlFor="is_active">Active</Label>
                    <p className="text-sm text-gray-500">
                      Product visible to customers
                    </p>
                  </div>
                  <Switch
                    id="is_active"
                    checked={formData.is_active}
                    onCheckedChange={(checked) =>
                      setFormData((prev) => ({ ...prev, is_active: checked }))
                    }
                  />
                </div>

                <div className="flex items-center justify-between">
                  <div>
                    <Label htmlFor="is_featured">Featured</Label>
                    <p className="text-sm text-gray-500">
                      Highlight this product
                    </p>
                  </div>
                  <Switch
                    id="is_featured"
                    checked={formData.is_featured}
                    onCheckedChange={(checked) =>
                      setFormData((prev) => ({ ...prev, is_featured: checked }))
                    }
                  />
                </div>
              </CardContent>
            </Card>

            <div className="flex flex-col gap-2">
              <Button type="submit" disabled={saving || !formData.name}>
                {saving ? (
                  <>
                    <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                    Saving...
                  </>
                ) : (
                  'Save Changes'
                )}
              </Button>
              <Link href="/showroom/products">
                <Button type="button" variant="outline" className="w-full">
                  Cancel
                </Button>
              </Link>
            </div>
          </div>
        </div>
      </form>
    </div>
  )
}
