'use client'

import { useState, useEffect, useCallback } from 'react'
import { createClient } from '@/lib/supabase/client'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Label } from '@/components/ui/label'
import { Textarea } from '@/components/ui/textarea'
import { Separator } from '@/components/ui/separator'
import {
  Loader2,
  Save,
  Bot,
  Info,
  RotateCcw,
  Sparkles,
} from 'lucide-react'
import { toast } from 'sonner'

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

export default function AdminSettingsPage() {
  const supabase = createClient()

  // State
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [systemPrompt, setSystemPrompt] = useState('')
  const [originalPrompt, setOriginalPrompt] = useState('')
  const [promptId, setPromptId] = useState<string | null>(null)

  // Load global default prompt
  useEffect(() => {
    async function loadPrompt() {
      setLoading(true)
      try {
        const { data } = await supabase
          .from('ai_system_prompts')
          .select('id, system_prompt')
          .is('showroom_id', null)
          .eq('is_active', true)
          .single()

        if (data) {
          setSystemPrompt(data.system_prompt)
          setOriginalPrompt(data.system_prompt)
          setPromptId(data.id)
        } else {
          // Use default
          setSystemPrompt(DEFAULT_SYSTEM_PROMPT)
          setOriginalPrompt(DEFAULT_SYSTEM_PROMPT)
        }
      } catch (error) {
        console.error('Error loading prompt:', error)
        setSystemPrompt(DEFAULT_SYSTEM_PROMPT)
        setOriginalPrompt(DEFAULT_SYSTEM_PROMPT)
      } finally {
        setLoading(false)
      }
    }

    loadPrompt()
  }, [supabase])

  // Check if there are unsaved changes
  const hasChanges = systemPrompt !== originalPrompt

  // Save prompt
  const handleSave = useCallback(async () => {
    setSaving(true)
    try {
      if (promptId) {
        // Update existing and verify it was updated
        const { data, error } = await supabase
          .from('ai_system_prompts')
          .update({
            system_prompt: systemPrompt,
            updated_at: new Date().toISOString(),
          })
          .eq('id', promptId)
          .select('id')

        if (error) throw error

        // Check if update actually happened (RLS might silently block it)
        if (!data || data.length === 0) {
          throw new Error('Update failed - you may not have permission to modify this prompt')
        }
      } else {
        // Insert new
        const { data, error } = await supabase
          .from('ai_system_prompts')
          .insert({
            showroom_id: null,
            prompt_name: 'Global Default',
            system_prompt: systemPrompt,
            is_active: true,
          })
          .select('id')
          .single()

        if (error) throw error
        setPromptId(data.id)
      }

      setOriginalPrompt(systemPrompt)
      toast.success('Global default prompt saved successfully')
    } catch (error) {
      console.error('Error saving prompt:', error)
      toast.error('Failed to save prompt')
    } finally {
      setSaving(false)
    }
  }, [systemPrompt, promptId, supabase])

  // Reset to default
  const handleResetToDefault = () => {
    setSystemPrompt(DEFAULT_SYSTEM_PROMPT)
  }

  // Reset changes
  const handleResetChanges = () => {
    setSystemPrompt(originalPrompt)
  }

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <Loader2 className="h-6 w-6 animate-spin text-gray-400" />
      </div>
    )
  }

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold">Settings</h1>
        <p className="text-gray-500">Global platform configuration</p>
      </div>

      {/* AI Designer Agent Global Settings */}
      <Card>
        <CardHeader>
          <div className="flex items-center gap-3">
            <div className="p-2 bg-purple-100 rounded-lg">
              <Bot className="h-6 w-6 text-purple-600" />
            </div>
            <div>
              <CardTitle>AI Designer Agent - Global Default</CardTitle>
              <CardDescription>
                Configure the default system prompt used for AI chatbot conversations. Individual showrooms can override this with their own custom prompt.
              </CardDescription>
            </div>
          </div>
        </CardHeader>

        <CardContent className="space-y-6">
          {/* Prompt Editor */}
          <div className="space-y-4">
            <div className="flex items-center justify-between">
              <Label className="text-base font-semibold">System Prompt</Label>
              <Button
                variant="outline"
                size="sm"
                onClick={handleResetToDefault}
                className="gap-2 text-xs"
              >
                <Sparkles className="h-3 w-3" />
                Reset to Factory Default
              </Button>
            </div>

            <Textarea
              value={systemPrompt}
              onChange={(e) => setSystemPrompt(e.target.value)}
              placeholder="Enter the default system prompt for AI assistants..."
              className="min-h-[300px] font-mono text-sm"
            />

            {/* Variables Info */}
            <div className="flex items-start gap-2 p-3 bg-blue-50 rounded-lg">
              <Info className="h-4 w-4 text-blue-600 mt-0.5 flex-shrink-0" />
              <div className="text-sm text-blue-700">
                <p className="font-medium mb-1">Available Variables:</p>
                <ul className="list-disc list-inside space-y-0.5 text-blue-600">
                  <li>
                    <code className="bg-blue-100 px-1 rounded">{'{showroom_name}'}</code> -
                    The showroom&apos;s business name
                  </li>
                  <li>
                    <code className="bg-blue-100 px-1 rounded">{'{customer_name}'}</code> -
                    Customer&apos;s name from their submission
                  </li>
                </ul>
                <p className="mt-2 text-blue-600">
                  All project data (room dimensions, products selected, floor plan) is automatically provided to the AI in the conversation context.
                </p>
              </div>
            </div>
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
                onClick={handleResetChanges}
                disabled={!hasChanges || saving}
                className="gap-2"
              >
                <RotateCcw className="h-4 w-4" />
                Discard Changes
              </Button>
              <Button
                onClick={handleSave}
                disabled={!hasChanges || saving}
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

      {/* Placeholder for future settings */}
      <Card className="border-dashed">
        <CardContent className="py-8 text-center text-gray-500">
          <p className="text-sm">More global settings coming soon...</p>
        </CardContent>
      </Card>
    </div>
  )
}
