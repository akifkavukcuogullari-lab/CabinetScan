'use client'

import { useState } from 'react'
import { createClient } from '@/lib/supabase/client'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Switch } from '@/components/ui/switch'
import { Loader2, CheckCircle, Settings2 } from 'lucide-react'

interface CustomConfigSettingsProps {
  showroom: {
    id: string
    name: string
    visualize_kitchen_enabled: boolean
  }
}

interface ConfigToggleProps {
  id: string
  label: string
  description: string
  checked: boolean
  onToggle: (checked: boolean) => void
  saving: boolean
  success: boolean
}

function ConfigToggle({ id, label, description, checked, onToggle, saving, success }: ConfigToggleProps) {
  return (
    <div className="flex items-center justify-between py-3 border-b last:border-b-0">
      <div className="flex-1">
        <label htmlFor={id} className="font-medium text-sm cursor-pointer">
          {label}
        </label>
        <p className="text-xs text-gray-500 mt-0.5">{description}</p>
      </div>
      <div className="flex items-center gap-2 ml-4">
        {saving && <Loader2 className="h-3 w-3 animate-spin text-gray-400" />}
        {success && <CheckCircle className="h-3 w-3 text-green-500" />}
        <Switch
          id={id}
          checked={checked}
          onCheckedChange={onToggle}
          disabled={saving}
        />
      </div>
    </div>
  )
}

export function CustomConfigSettings({ showroom }: CustomConfigSettingsProps) {
  const supabase = createClient()

  // Visualize Kitchen state
  const [visualizeKitchenEnabled, setVisualizeKitchenEnabled] = useState(showroom.visualize_kitchen_enabled)
  const [savingVisualize, setSavingVisualize] = useState(false)
  const [successVisualize, setSuccessVisualize] = useState(false)

  const toggleVisualizeKitchen = async (enabled: boolean) => {
    setSavingVisualize(true)
    setSuccessVisualize(false)

    const { error } = await supabase
      .from('showrooms')
      .update({ visualize_kitchen_enabled: enabled })
      .eq('id', showroom.id)

    setSavingVisualize(false)

    if (error) {
      console.error('Error updating visualize kitchen setting:', error)
    } else {
      setVisualizeKitchenEnabled(enabled)
      setSuccessVisualize(true)
      setTimeout(() => setSuccessVisualize(false), 2000)
    }
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <Settings2 className="h-5 w-5" />
          Custom Configs
        </CardTitle>
        <CardDescription>
          Configure custom features for {showroom.name}. These settings are independent of the subscription plan.
        </CardDescription>
      </CardHeader>
      <CardContent>
        <ConfigToggle
          id="visualize-kitchen"
          label="Visualize Kitchen"
          description="Show AI-powered kitchen visualization button on project pages"
          checked={visualizeKitchenEnabled}
          onToggle={toggleVisualizeKitchen}
          saving={savingVisualize}
          success={successVisualize}
        />
        {/* Add more toggles here in the future */}
      </CardContent>
    </Card>
  )
}
