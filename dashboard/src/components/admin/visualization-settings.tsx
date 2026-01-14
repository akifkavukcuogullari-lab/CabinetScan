'use client'

import { useState } from 'react'
import { createClient } from '@/lib/supabase/client'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Switch } from '@/components/ui/switch'
import { Label } from '@/components/ui/label'
import { Loader2, CheckCircle, AlertCircle, Sparkles } from 'lucide-react'

interface VisualizationSettingsProps {
  showroom: {
    id: string
    name: string
    visualize_kitchen_enabled: boolean
  }
}

export function VisualizationSettings({ showroom }: VisualizationSettingsProps) {
  const supabase = createClient()
  const [visualizeKitchenEnabled, setVisualizeKitchenEnabled] = useState(showroom.visualize_kitchen_enabled)
  const [saving, setSaving] = useState(false)
  const [success, setSuccess] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const toggleVisualizeKitchen = async (enabled: boolean) => {
    setSaving(true)
    setError(null)
    setSuccess(false)

    const { error: updateError } = await supabase
      .from('showrooms')
      .update({ visualize_kitchen_enabled: enabled })
      .eq('id', showroom.id)

    setSaving(false)

    if (updateError) {
      setError('Failed to update visualization setting')
      console.error('Error updating visualization setting:', updateError)
    } else {
      setVisualizeKitchenEnabled(enabled)
      setSuccess(true)
      setTimeout(() => setSuccess(false), 3000)
    }
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <Sparkles className="h-5 w-5 text-purple-600" />
          Kitchen Visualization
        </CardTitle>
        <CardDescription>
          Configure AI-powered kitchen visualization features for this showroom.
          This setting is independent of the subscription plan.
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-6">
        {/* Visualize Kitchen Toggle */}
        <div className="flex items-center justify-between p-4 bg-gradient-to-r from-purple-50 to-blue-50 rounded-lg border border-purple-100">
          <div className="flex items-center gap-4">
            <div className="p-2 bg-white rounded-lg shadow-sm">
              <Sparkles className="h-5 w-5 text-purple-600" />
            </div>
            <div>
              <Label htmlFor="visualize-kitchen" className="font-medium">
                Visualize Kitchen Button
              </Label>
              <p className="text-sm text-gray-500 mt-1">
                When enabled, showroom owners can use the &quot;Visualize Kitchen&quot; feature on project pages
              </p>
            </div>
          </div>
          <div className="flex items-center gap-3">
            {saving && <Loader2 className="h-4 w-4 animate-spin text-gray-400" />}
            {success && <CheckCircle className="h-4 w-4 text-green-500" />}
            <Switch
              id="visualize-kitchen"
              checked={visualizeKitchenEnabled}
              onCheckedChange={toggleVisualizeKitchen}
              disabled={saving}
            />
          </div>
        </div>

        {error && (
          <div className="flex items-center gap-2 text-sm text-red-600 bg-red-50 p-3 rounded-lg">
            <AlertCircle className="h-4 w-4 flex-shrink-0" />
            {error}
          </div>
        )}

        {/* Info Box */}
        <div className="bg-blue-50 border border-blue-100 rounded-lg p-4">
          <h4 className="text-sm font-medium text-blue-900 mb-2">How it works</h4>
          <ul className="text-sm text-blue-800 space-y-1">
            <li>• When enabled, a &quot;Visualize Kitchen&quot; button appears on project detail pages</li>
            <li>• Showroom owners can click it to generate AI-powered kitchen visualizations</li>
            <li>• The visualization uses the Cabinet AI service to create design previews</li>
            <li>• This feature is controlled by Super Admin, independent of subscription plan</li>
          </ul>
        </div>

        {/* Current Status */}
        <div className="text-sm text-gray-500">
          <span className="font-medium">Current Status:</span>{' '}
          {visualizeKitchenEnabled ? (
            <span className="text-green-600 font-medium">Enabled</span>
          ) : (
            <span className="text-gray-400">Disabled</span>
          )}
          {' for '}<span className="font-medium">{showroom.name}</span>
        </div>
      </CardContent>
    </Card>
  )
}
