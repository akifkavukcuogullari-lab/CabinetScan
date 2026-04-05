'use client'

import { useState, useEffect } from 'react'
import { createClient } from '@/lib/supabase/client'

/**
 * Hook to check if the Voice Agent feature is enabled globally
 * and for a specific showroom.
 */
export function useVoiceAgentEnabled(showroomId?: string) {
  const [globalEnabled, setGlobalEnabled] = useState(false)
  const [showroomEnabled, setShowroomEnabled] = useState(false)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    async function check() {
      const supabase = createClient()

      // Check global toggle
      const { data: globalSetting } = await supabase
        .from('platform_settings')
        .select('value')
        .eq('key', 'voice_agent_globally_enabled')
        .single()

      const isGlobal = globalSetting?.value === 'true'
      setGlobalEnabled(isGlobal)

      // Check showroom toggle if showroomId provided
      if (isGlobal && showroomId) {
        const { data: showroomSetting } = await supabase
          .from('voice_agent_showroom_settings')
          .select('enabled')
          .eq('showroom_id', showroomId)
          .single()

        setShowroomEnabled(showroomSetting?.enabled ?? false)
      }

      setLoading(false)
    }

    check()
  }, [showroomId])

  return { globalEnabled, showroomEnabled, loading }
}
