'use client'

import { useState, useEffect } from 'react'
import { createClient } from '@/lib/supabase/client'
import { Card, CardContent } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Textarea } from '@/components/ui/textarea'
import { Switch } from '@/components/ui/switch'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { Plus, Trash2, Loader2, AlertCircle, Upload, X, Package, Sparkles, Edit2 } from 'lucide-react'
import Image from 'next/image'

interface ShowroomAddon {
  id: string
  showroom_id: string
  question: string
  description: string | null
  unit: string
  is_enabled: boolean
  display_order: number
  price_per_unit: number | null
  image_url: string | null
  use_color_coefficient: boolean
}

interface CustomAddonsProps {
  showroomId: string
}

export function CustomAddons({ showroomId }: CustomAddonsProps) {
  const supabase = createClient()
  const [addons, setAddons] = useState<ShowroomAddon[]>([])
  const [loading, setLoading] = useState(true)
  const [showDialog, setShowDialog] = useState(false)
  const [editingAddon, setEditingAddon] = useState<ShowroomAddon | null>(null)

  // Form state
  const [addonQuestion, setAddonQuestion] = useState('')
  const [addonDescription, setAddonDescription] = useState('')
  const [addonUnit, setAddonUnit] = useState('pieces')
  const [addonPrice, setAddonPrice] = useState('')
  const [useColorCoefficient, setUseColorCoefficient] = useState(false)
  const [imageFile, setImageFile] = useState<File | null>(null)
  const [imagePreview, setImagePreview] = useState<string | null>(null)
  const [uploading, setUploading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    loadAddons()
  }, [showroomId])

  const loadAddons = async () => {
    setLoading(true)
    const { data, error } = await supabase
      .from('showroom_addons')
      .select('*')
      .eq('showroom_id', showroomId)
      .order('display_order')

    if (data) {
      setAddons(data)

      // Create default addon if none exist
      if (data.length === 0) {
        const { data: defaultAddon } = await supabase
          .from('showroom_addons')
          .insert({
            showroom_id: showroomId,
            question: 'Add trash can?',
            description: 'Include a pull-out trash can system',
            unit: 'pieces',
            is_enabled: true,
            display_order: 0,
            price_per_unit: 150.00
          })
          .select()
          .single()

        if (defaultAddon) setAddons([defaultAddon])
      }
    }
    setLoading(false)
  }

  const handleImageChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    if (!file) return

    // Validate file type
    if (!file.type.startsWith('image/')) {
      setError('Please select an image file')
      return
    }

    // Validate file size (5MB max)
    if (file.size > 5 * 1024 * 1024) {
      setError('Image must be less than 5MB')
      return
    }

    setImageFile(file)
    setError(null)

    // Create preview
    const reader = new FileReader()
    reader.onloadend = () => {
      setImagePreview(reader.result as string)
    }
    reader.readAsDataURL(file)
  }

  const uploadImage = async (): Promise<string | null> => {
    if (!imageFile) return null

    const fileExt = imageFile.name.split('.').pop()
    const fileName = `${showroomId}/${Date.now()}.${fileExt}`

    const { error: uploadError } = await supabase.storage
      .from('products')
      .upload(fileName, imageFile)

    if (uploadError) {
      setError('Failed to upload image')
      return null
    }

    const { data: { publicUrl } } = supabase.storage
      .from('products')
      .getPublicUrl(fileName)

    return publicUrl
  }

  const saveAddon = async () => {
    if (!addonQuestion.trim()) {
      setError('Question is required')
      return
    }

    setUploading(true)
    setError(null)

    // Upload new image if selected
    let imageUrl = editingAddon?.image_url || null
    if (imageFile) {
      // Delete old image if updating and had an old image
      if (editingAddon?.image_url) {
        const oldPath = editingAddon.image_url.split('/products/')[1]
        if (oldPath) {
          await supabase.storage.from('products').remove([oldPath])
        }
      }

      imageUrl = await uploadImage()
      if (!imageUrl && imageFile) {
        setUploading(false)
        return
      }
    }

    if (editingAddon) {
      // Update existing addon
      const { data, error: updateError } = await supabase
        .from('showroom_addons')
        .update({
          question: addonQuestion.trim(),
          description: addonDescription.trim() || null,
          unit: addonUnit,
          price_per_unit: addonPrice ? parseFloat(addonPrice) : null,
          use_color_coefficient: useColorCoefficient,
          image_url: imageUrl
        })
        .eq('id', editingAddon.id)
        .select()
        .single()

      setUploading(false)

      if (updateError) {
        setError('Failed to update custom item')
      } else if (data) {
        setAddons((prev) => prev.map((addon) => (addon.id === data.id ? data : addon)))
        resetForm()
        setShowDialog(false)
      }
    } else {
      // Insert new addon
      const { data, error: insertError } = await supabase
        .from('showroom_addons')
        .insert({
          showroom_id: showroomId,
          question: addonQuestion.trim(),
          description: addonDescription.trim() || null,
          unit: addonUnit,
          is_enabled: true,
          display_order: addons.length,
          price_per_unit: addonPrice ? parseFloat(addonPrice) : null,
          use_color_coefficient: useColorCoefficient,
          image_url: imageUrl
        })
        .select()
        .single()

      setUploading(false)

      if (insertError) {
        setError('Failed to add custom item')
      } else if (data) {
        setAddons([...addons, data])
        resetForm()
        setShowDialog(false)
      }
    }
  }

  const openAddDialog = () => {
    setEditingAddon(null)
    resetForm()
    setShowDialog(true)
  }

  const openEditDialog = (addon: ShowroomAddon) => {
    setEditingAddon(addon)
    setAddonQuestion(addon.question)
    setAddonDescription(addon.description || '')
    setAddonUnit(addon.unit)
    setAddonPrice(addon.price_per_unit ? addon.price_per_unit.toString() : '')
    setUseColorCoefficient(addon.use_color_coefficient || false)
    setImagePreview(addon.image_url)
    setImageFile(null)
    setError(null)
    setShowDialog(true)
  }

  const resetForm = () => {
    setEditingAddon(null)
    setAddonQuestion('')
    setAddonDescription('')
    setAddonUnit('pieces')
    setAddonPrice('')
    setUseColorCoefficient(false)
    setImageFile(null)
    setImagePreview(null)
    setError(null)
  }

  const toggleAddon = async (addonId: string, enabled: boolean) => {
    await supabase
      .from('showroom_addons')
      .update({ is_enabled: enabled })
      .eq('id', addonId)

    setAddons((prev) =>
      prev.map((addon) =>
        addon.id === addonId ? { ...addon, is_enabled: enabled } : addon
      )
    )
  }

  const deleteAddon = async (addonId: string) => {
    if (!confirm('Are you sure you want to delete this custom item?')) return

    const addon = addons.find(a => a.id === addonId)

    // Delete image from storage if exists
    if (addon?.image_url) {
      const path = addon.image_url.split('/products/')[1]
      if (path) {
        await supabase.storage.from('products').remove([path])
      }
    }

    await supabase
      .from('showroom_addons')
      .delete()
      .eq('id', addonId)

    setAddons((prev) => prev.filter((addon) => addon.id !== addonId))
  }

  if (loading) {
    return (
      <div className="flex items-center justify-center py-12">
        <Loader2 className="h-8 w-8 animate-spin text-gray-400" />
      </div>
    )
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between mb-4">
        <div>
          <h2 className="text-lg font-semibold flex items-center gap-2">
            <Sparkles className="h-5 w-5 text-purple-600" />
            Custom Addon Items
          </h2>
          <p className="text-sm text-gray-500 mt-1">
            Create custom yes/no questions with images that appear after product selections in the iOS app
          </p>
        </div>
        <Button onClick={openAddDialog}>
          <Plus className="h-4 w-4 mr-2" />
          Add Custom Item
        </Button>
      </div>

      {addons.length > 0 ? (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {addons.map((addon) => (
            <Card key={addon.id} className="overflow-hidden">
              <div className="aspect-square relative bg-gray-100">
                {addon.image_url ? (
                  <Image
                    src={addon.image_url}
                    alt={addon.question}
                    fill
                    className="object-cover"
                  />
                ) : (
                  <div className="flex items-center justify-center h-full">
                    <Package className="h-12 w-12 text-gray-300" />
                  </div>
                )}
                <div className="absolute top-2 right-2">
                  <Switch
                    checked={addon.is_enabled}
                    onCheckedChange={(checked) => toggleAddon(addon.id, checked)}
                    className="bg-white shadow-md"
                  />
                </div>
              </div>
              <CardContent className="p-4">
                <div className="space-y-2">
                  <div className="flex items-start justify-between gap-2">
                    <h3 className="font-medium flex-1">{addon.question}</h3>
                    <Badge variant={addon.is_enabled ? 'default' : 'secondary'} className="shrink-0">
                      {addon.is_enabled ? 'Active' : 'Inactive'}
                    </Badge>
                  </div>

                  {addon.description && (
                    <p className="text-sm text-gray-500 line-clamp-2">{addon.description}</p>
                  )}

                  <div className="flex items-center gap-2 text-xs text-gray-500">
                    <span>Unit: {addon.unit}</span>
                    {addon.price_per_unit && (
                      <>
                        <span>•</span>
                        <span className="font-medium text-gray-900">
                          ${addon.price_per_unit.toFixed(2)}
                        </span>
                      </>
                    )}
                    {addon.use_color_coefficient && (
                      <>
                        <span>•</span>
                        <Badge variant="outline" className="text-xs">
                          Color coeff.
                        </Badge>
                      </>
                    )}
                  </div>

                  <div className="flex gap-2 mt-2">
                    <Button
                      variant="outline"
                      size="sm"
                      onClick={() => openEditDialog(addon)}
                      className="flex-1"
                    >
                      <Edit2 className="h-4 w-4 mr-2" />
                      Edit
                    </Button>
                    <Button
                      variant="ghost"
                      size="sm"
                      onClick={() => deleteAddon(addon.id)}
                      className="flex-1 text-red-600 hover:text-red-700 hover:bg-red-50"
                    >
                      <Trash2 className="h-4 w-4 mr-2" />
                      Delete
                    </Button>
                  </div>
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
      ) : (
        <Card>
          <CardContent className="py-10 text-center">
            <Sparkles className="h-12 w-12 mx-auto text-purple-400 mb-4" />
            <h3 className="text-lg font-medium mb-2">
              No custom addon items yet
            </h3>
            <p className="text-gray-500 mb-4">
              Add custom items like trash cans, wine racks, or any extra accessories
            </p>
            <Button onClick={openAddDialog}>
              <Plus className="h-4 w-4 mr-2" />
              Add Your First Item
            </Button>
          </CardContent>
        </Card>
      )}

      {/* Add/Edit Custom Addon Dialog */}
      <Dialog open={showDialog} onOpenChange={(open) => {
        setShowDialog(open)
        if (!open) resetForm()
      }}>
        <DialogContent className="max-w-md max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>
              {editingAddon ? 'Edit Custom Addon Item' : 'Add Custom Addon Item'}
            </DialogTitle>
            <DialogDescription>
              {editingAddon
                ? 'Update the addon item details and image'
                : 'Create a yes/no question with an image to show customers after product selection'
              }
            </DialogDescription>
          </DialogHeader>

          <div className="space-y-4">
            {/* Image Upload */}
            <div>
              <Label htmlFor="image">Image {!editingAddon && '*'}</Label>
              <div className="mt-2">
                {imagePreview ? (
                  <div className="relative aspect-square rounded-lg overflow-hidden border">
                    <Image
                      src={imagePreview}
                      alt="Preview"
                      fill
                      className="object-cover"
                    />
                    <button
                      type="button"
                      onClick={() => {
                        setImageFile(null)
                        setImagePreview(editingAddon?.image_url || null)
                      }}
                      className="absolute top-2 right-2 p-1.5 bg-white rounded-full shadow-md hover:bg-gray-100"
                    >
                      <X className="h-4 w-4" />
                    </button>
                  </div>
                ) : (
                  <label
                    htmlFor="image"
                    className="flex flex-col items-center justify-center aspect-square rounded-lg border-2 border-dashed border-gray-300 hover:border-gray-400 cursor-pointer bg-gray-50 hover:bg-gray-100 transition-colors"
                  >
                    <Upload className="h-8 w-8 text-gray-400 mb-2" />
                    <span className="text-sm text-gray-600">Click to upload image</span>
                    <span className="text-xs text-gray-500 mt-1">PNG, JPG up to 5MB</span>
                    <input
                      id="image"
                      type="file"
                      accept="image/*"
                      onChange={handleImageChange}
                      className="hidden"
                    />
                  </label>
                )}
              </div>
            </div>

            {/* Question */}
            <div>
              <Label htmlFor="question">Question *</Label>
              <Input
                id="question"
                value={addonQuestion}
                onChange={(e) => {
                  setAddonQuestion(e.target.value)
                  setError(null)
                }}
                placeholder="Add trash can?"
              />
            </div>

            {/* Description */}
            <div>
              <Label htmlFor="description">Description (Optional)</Label>
              <Textarea
                id="description"
                value={addonDescription}
                onChange={(e) => setAddonDescription(e.target.value)}
                placeholder="Include a pull-out trash can system"
                rows={2}
              />
            </div>

            {/* Unit and Price */}
            <div className="grid grid-cols-2 gap-4">
              <div>
                <Label htmlFor="unit">Unit</Label>
                <Select value={addonUnit} onValueChange={setAddonUnit}>
                  <SelectTrigger id="unit">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="pieces">Pieces</SelectItem>
                    <SelectItem value="units">Units</SelectItem>
                    <SelectItem value="sets">Sets</SelectItem>
                  </SelectContent>
                </Select>
              </div>

              <div>
                <Label htmlFor="price">Price (Optional)</Label>
                <Input
                  id="price"
                  type="number"
                  step="0.01"
                  value={addonPrice}
                  onChange={(e) => setAddonPrice(e.target.value)}
                  placeholder="150.00"
                />
              </div>
            </div>

            {/* Color Coefficient Toggle */}
            <div className="flex items-center justify-between p-3 bg-gray-50 rounded-lg">
              <div>
                <Label htmlFor="use_color_coefficient" className="text-sm font-medium">
                  Apply Cabinet Color Coefficient
                </Label>
                <p className="text-xs text-gray-500 mt-0.5">
                  Price multiplied by cabinet color coefficient
                </p>
              </div>
              <Switch
                id="use_color_coefficient"
                checked={useColorCoefficient}
                onCheckedChange={setUseColorCoefficient}
              />
            </div>

            {error && (
              <div className="flex items-center gap-2 text-sm text-red-600 bg-red-50 p-3 rounded-lg">
                <AlertCircle className="h-4 w-4 flex-shrink-0" />
                {error}
              </div>
            )}

            <div className="flex gap-2 justify-end pt-4">
              <Button
                variant="outline"
                onClick={() => {
                  setShowDialog(false)
                  resetForm()
                }}
                disabled={uploading}
              >
                Cancel
              </Button>
              <Button
                onClick={saveAddon}
                disabled={uploading}
              >
                {uploading ? (
                  <>
                    <Loader2 className="h-4 w-4 mr-2 animate-spin" />
                    {editingAddon ? 'Updating...' : 'Adding...'}
                  </>
                ) : (
                  <>
                    {editingAddon ? (
                      <>
                        <Edit2 className="h-4 w-4 mr-2" />
                        Update Item
                      </>
                    ) : (
                      <>
                        <Plus className="h-4 w-4 mr-2" />
                        Add Item
                      </>
                    )}
                  </>
                )}
              </Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  )
}
