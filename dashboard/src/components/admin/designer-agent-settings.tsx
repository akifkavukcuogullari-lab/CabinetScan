'use client'

import { useState, useCallback, useEffect } from 'react'
import { createClient } from '@/lib/supabase/client'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Label } from '@/components/ui/label'
import { Textarea } from '@/components/ui/textarea'
import { Switch } from '@/components/ui/switch'
import { Separator } from '@/components/ui/separator'
import {
  Loader2,
  Save,
  Bot,
  Info,
  RotateCcw,
} from 'lucide-react'
import { useRouter } from 'next/navigation'
import { toast } from 'sonner'

interface DesignerAgentSettingsProps {
  showroom: {
    id: string
    name: string
    ai_chatbot_enabled: boolean
  }
}

const DEFAULT_SYSTEM_PROMPT = `You are a friendly interior design assistant for {showroom_name}.

Your personality:
- Warm and enthusiastic about design
- Ask one question at a time
- Use {customer_name}'s name naturally in conversation
- Show genuine interest in their vision
- Keep responses concise (2-3 sentences max)
- Use conversational language, not formal

Your goal: Learn about their style preferences, timeline, budget comfort, and any special requirements. Make them feel heard and excited about their project.

Important guidelines:
- Never discuss pricing or give quotes
- Focus on design preferences and project details
- If asked about costs, explain that the showroom team will provide a detailed quote
- Be helpful but redirect business questions to the showroom staff`

export function DesignerAgentSettings({ showroom }: DesignerAgentSettingsProps) {
  const router = useRouter()
  const supabase = createClient()

  // Form state
  const [systemPrompt, setSystemPrompt] = useState('')
  const [useGlobalDefault, setUseGlobalDefault] = useState(true)
  const [globalPrompt, setGlobalPrompt] = useState('')
  const [originalPrompt, setOriginalPrompt] = useState('')
  const [originalUseGlobal, setOriginalUseGlobal] = useState(true)

  // UI state
  const [saving, setSaving] = useState(false)
  const [loadingPrompt, setLoadingPrompt] = useState(true)

  // Load system prompts on mount
  useEffect(() => {
    async function loadPrompts() {
      setLoadingPrompt(true)
      try {
        // Get global default prompt
        const { data: globalData } = await supabase
          .from('ai_system_prompts')
          .select('system_prompt')
          .is('showroom_id', null)
          .eq('is_active', true)
          .single()

        if (globalData) {
          setGlobalPrompt(globalData.system_prompt)
        }

        // Check if showroom has custom prompt
        const { data: customData } = await supabase
          .from('ai_system_prompts')
          .select('system_prompt')
          .eq('showroom_id', showroom.id)
          .eq('is_active', true)
          .single()

        if (customData) {
          setSystemPrompt(customData.system_prompt)
          setOriginalPrompt(customData.system_prompt)
          setUseGlobalDefault(false)
          setOriginalUseGlobal(false)
        } else {
          const prompt = globalData?.system_prompt || DEFAULT_SYSTEM_PROMPT
          setSystemPrompt(prompt)
          setOriginalPrompt(prompt)
          setUseGlobalDefault(true)
          setOriginalUseGlobal(true)
        }
      } catch (error) {
        console.error('Error loading prompts:', error)
        setSystemPrompt(DEFAULT_SYSTEM_PROMPT)
        setOriginalPrompt(DEFAULT_SYSTEM_PROMPT)
      } finally {
        setLoadingPrompt(false)
      }
    }

    loadPrompts()
  }, [showroom.id, supabase])

  // Detect changes
  const hasChanges =
    useGlobalDefault !== originalUseGlobal ||
    (!useGlobalDefault && systemPrompt !== originalPrompt)

  // Handle save
  const handleSave = useCallback(async () => {
    setSaving(true)
    try {
      // Handle system prompt
      if (useGlobalDefault) {
        // Delete custom prompt if exists
        await supabase
          .from('ai_system_prompts')
          .delete()
          .eq('showroom_id', showroom.id)
      } else {
        // Upsert custom prompt
        const { error: promptError } = await supabase
          .from('ai_system_prompts')
          .upsert(
            {
              showroom_id: showroom.id,
              prompt_name: `${showroom.name} Custom`,
              system_prompt: systemPrompt,
              is_active: true,
            },
            { onConflict: 'showroom_id' }
          )

        if (promptError) throw promptError
      }

      // Update original values
      setOriginalPrompt(systemPrompt)
      setOriginalUseGlobal(useGlobalDefault)

      toast.success('System prompt saved', {
        description: useGlobalDefault
          ? 'Using global default prompt'
          : 'Custom prompt saved for this showroom',
      })
      router.refresh()
    } catch (error) {
      console.error('Error saving settings:', error)
      toast.error('Failed to save settings')
    } finally {
      setSaving(false)
    }
  }, [
    useGlobalDefault,
    systemPrompt,
    showroom.id,
    showroom.name,
    supabase,
    router,
  ])

  // Reset form
  const handleReset = () => {
    setSystemPrompt(originalPrompt)
    setUseGlobalDefault(originalUseGlobal)
  }

  return (
    <Card>
      <CardHeader>
        <div className="flex items-center gap-3">
          <div className="p-2 bg-purple-100 rounded-lg">
            <Bot className="h-6 w-6 text-purple-600" />
          </div>
          <div>
            <CardTitle>AI Designer Agent - System Prompt</CardTitle>
            <CardDescription>
              Configure the AI behavior and conversation style for this showroom.
              Showroom owners can set their own assistant name and avatar in their settings.
            </CardDescription>
          </div>
        </div>
      </CardHeader>

      <CardContent className="space-y-6">
        {/* System Prompt */}
        <div className="space-y-4">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2">
              <Bot className="h-4 w-4 text-purple-600" />
              <Label className="text-base font-semibold">System Prompt</Label>
            </div>
            <div className="flex items-center gap-2">
              <Switch
                id="use-global"
                checked={useGlobalDefault}
                onCheckedChange={(checked) => {
                  setUseGlobalDefault(checked)
                  if (checked) {
                    setSystemPrompt(globalPrompt || DEFAULT_SYSTEM_PROMPT)
                  }
                }}
              />
              <Label htmlFor="use-global" className="text-sm text-gray-600">
                Use global default
              </Label>
            </div>
          </div>

          {loadingPrompt ? (
            <div className="flex items-center justify-center py-8">
              <Loader2 className="h-6 w-6 animate-spin text-gray-400" />
            </div>
          ) : (
            <>
              <Textarea
                value={systemPrompt}
                onChange={(e) => setSystemPrompt(e.target.value)}
                placeholder="Enter the system prompt for the AI assistant..."
                className="min-h-[200px] font-mono text-sm"
                disabled={useGlobalDefault}
              />

              <div className="flex items-start gap-2 p-3 bg-blue-50 rounded-lg">
                <Info className="h-4 w-4 text-blue-600 mt-0.5 flex-shrink-0" />
                <div className="text-sm text-blue-700">
                  <p className="font-medium mb-1">Available Variables:</p>
                  <ul className="list-disc list-inside space-y-0.5 text-blue-600">
                    <li>
                      <code className="bg-blue-100 px-1 rounded">{'{showroom_name}'}</code> -
                      Your showroom name
                    </li>
                    <li>
                      <code className="bg-blue-100 px-1 rounded">{'{customer_name}'}</code> -
                      Customer&apos;s name from the project
                    </li>
                  </ul>
                  <p className="mt-2 text-blue-600">
                    All project data (room size, products selected, floor plan) is
                    automatically provided to the AI.
                  </p>
                </div>
              </div>
            </>
          )}
        </div>

        <Separator />

        {/* Action Buttons */}
        <div className="flex items-center justify-between pt-2">
          <div className="text-sm text-gray-500">
            {hasChanges ? (
              <span className="flex items-center gap-1.5 text-amber-600">
                <span className="h-2 w-2 rounded-full bg-amber-500 animate-pulse" />
                Unsaved changes
              </span>
            ) : (
              <span className="text-gray-400">No changes</span>
            )}
          </div>
          <div className="flex gap-3">
            <Button
              variant="outline"
              onClick={handleReset}
              disabled={!hasChanges || saving}
              className="gap-2"
            >
              <RotateCcw className="h-4 w-4" />
              Reset
            </Button>
            <Button
              onClick={handleSave}
              disabled={saving}
              className="gap-2 min-w-[140px]"
            >
              {saving ? (
                <>
                  <Loader2 className="h-4 w-4 animate-spin" />
                  Saving...
                </>
              ) : (
                <>
                  <Save className="h-4 w-4" />
                  Save Changes
                </>
              )}
            </Button>
          </div>
        </div>
      </CardContent>
    </Card>
  )
}
