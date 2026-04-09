'use client'

import { memo } from 'react'
import { Handle, Position, type NodeProps } from 'reactflow'
import { PhoneCall } from 'lucide-react'

interface RetryCallNodeData {
  maxAttempts: number
}

function RetryCallNodeComponent({ data }: NodeProps<RetryCallNodeData>) {
  return (
    <div className="relative min-w-[180px] rounded-lg border-2 border-orange-300 bg-orange-50 px-4 py-3 shadow-sm">
      <Handle
        type="target"
        position={Position.Left}
        className="!h-3 !w-3 !border-2 !border-orange-400 !bg-orange-200"
      />
      <div className="flex items-center gap-2">
        <PhoneCall className="size-4 shrink-0 text-orange-600" />
        <span className="text-sm font-semibold text-orange-900">
          Retry Call (max {data.maxAttempts})
        </span>
      </div>
      {/* Default continue output */}
      <Handle
        type="source"
        position={Position.Bottom}
        id="continue"
        className="!h-3 !w-3 !border-2 !border-orange-400 !bg-orange-200"
      />
      {/* Max reached output */}
      <Handle
        type="source"
        position={Position.Right}
        id="max_reached"
        className="!h-3 !w-3 !border-2 !border-red-400 !bg-red-200"
      />
      <span className="absolute -right-1 top-1/2 translate-x-full -translate-y-1/2 text-[10px] font-medium text-red-600 pl-2">
        Max Reached
      </span>
    </div>
  )
}

export const RetryCallNode = memo(RetryCallNodeComponent)
