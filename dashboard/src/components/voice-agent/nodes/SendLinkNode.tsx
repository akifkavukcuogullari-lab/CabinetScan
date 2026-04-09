'use client'

import { memo } from 'react'
import { Handle, Position, type NodeProps } from 'reactflow'
import { Link } from 'lucide-react'

function SendLinkNodeComponent(_props: NodeProps) {
  return (
    <div className="min-w-[180px] rounded-lg border-2 border-purple-300 bg-purple-50 px-4 py-3 shadow-sm">
      <Handle
        type="target"
        position={Position.Left}
        className="!h-3 !w-3 !border-2 !border-purple-400 !bg-purple-200"
      />
      <div className="flex items-center gap-2">
        <Link className="size-4 shrink-0 text-purple-600" />
        <span className="text-sm font-semibold text-purple-900">
          Send Scheduling Link
        </span>
      </div>
      <Handle
        type="source"
        position={Position.Right}
        className="!h-3 !w-3 !border-2 !border-purple-400 !bg-purple-200"
      />
    </div>
  )
}

export const SendLinkNode = memo(SendLinkNodeComponent)
