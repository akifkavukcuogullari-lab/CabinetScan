'use client'

import { memo } from 'react'
import { Handle, Position, type NodeProps } from 'reactflow'
import { Clock } from 'lucide-react'

interface WaitNodeData {
  hours: number
  mode?: 'hours' | 'next_business_day'
}

function formatWait(data: WaitNodeData): string {
  if (data.mode === 'next_business_day') {
    return 'Next business day'
  }
  if (data.hours >= 24 && data.hours % 24 === 0) {
    const days = data.hours / 24
    return `Wait ${days}d`
  }
  return `Wait ${data.hours}h`
}

function WaitNodeComponent({ data }: NodeProps<WaitNodeData>) {
  return (
    <div className="min-w-[180px] rounded-lg border-2 border-gray-300 bg-gray-50 px-4 py-3 shadow-sm">
      <Handle
        type="target"
        position={Position.Left}
        className="!h-3 !w-3 !border-2 !border-gray-400 !bg-gray-200"
      />
      <div className="flex items-center gap-2">
        <Clock className="size-4 shrink-0 text-gray-500" />
        <span className="text-sm font-medium text-gray-700">
          {formatWait(data)}
        </span>
      </div>
      <Handle
        type="source"
        position={Position.Right}
        className="!h-3 !w-3 !border-2 !border-gray-400 !bg-gray-200"
      />
    </div>
  )
}

export const WaitNode = memo(WaitNodeComponent)
