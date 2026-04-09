'use client'

import { memo } from 'react'
import { Handle, Position, type NodeProps } from 'reactflow'
import { Square } from 'lucide-react'

function StopNodeComponent(_props: NodeProps) {
  return (
    <div className="min-w-[120px] rounded-lg border-2 border-red-300 bg-red-50 px-4 py-3 shadow-sm">
      <Handle
        type="target"
        position={Position.Left}
        className="!h-3 !w-3 !border-2 !border-red-400 !bg-red-200"
      />
      <div className="flex items-center gap-2">
        <Square className="size-4 shrink-0 text-red-600" />
        <span className="text-sm font-semibold text-red-900">Stop</span>
      </div>
    </div>
  )
}

export const StopNode = memo(StopNodeComponent)
