'use client'

import { useState } from 'react'
import {
  Dialog,
  DialogContent,
} from '@/components/ui/dialog'
import { X } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'

interface WhiteboardEntry {
  id: string
  entry_type: 'drawing' | 'photo'
  title: string | null
  thumbnail_url: string | null
  photo_url: string | null
  created_at: string | null
}

interface WhiteboardGalleryProps {
  whiteboards: WhiteboardEntry[]
}

export function WhiteboardGallery({ whiteboards }: WhiteboardGalleryProps) {
  const [selectedIndex, setSelectedIndex] = useState<number | null>(null)

  const getDisplayUrl = (entry: WhiteboardEntry) => {
    return entry.entry_type === 'drawing' ? entry.thumbnail_url : entry.photo_url
  }

  const getLabel = (entry: WhiteboardEntry) => {
    return entry.title || (entry.entry_type === 'drawing' ? 'Drawing' : 'Photo')
  }

  return (
    <>
      <div className="grid grid-cols-2 sm:grid-cols-3 gap-3">
        {whiteboards.map((entry, idx) => {
          const url = getDisplayUrl(entry)
          if (!url) return null

          return (
            <button
              key={entry.id}
              className="relative aspect-video rounded-lg overflow-hidden bg-gray-100 hover:ring-2 hover:ring-orange-400 transition-all cursor-pointer group"
              onClick={() => setSelectedIndex(idx)}
            >
              <img
                src={url}
                alt={getLabel(entry)}
                className="w-full h-full object-cover group-hover:scale-105 transition-transform duration-200"
              />
              <div className="absolute bottom-0 inset-x-0 bg-gradient-to-t from-black/60 to-transparent p-2">
                <div className="flex items-center gap-1.5">
                  <Badge
                    variant="secondary"
                    className="text-[10px] px-1.5 py-0 bg-white/20 text-white border-none"
                  >
                    {entry.entry_type === 'drawing' ? 'Drawing' : 'Photo'}
                  </Badge>
                  <p className="text-xs text-white truncate">{getLabel(entry)}</p>
                </div>
              </div>
            </button>
          )
        })}
      </div>

      <Dialog open={selectedIndex !== null} onOpenChange={() => setSelectedIndex(null)}>
        <DialogContent className="max-w-4xl p-0 overflow-hidden bg-black/95 border-none">
          <div className="relative flex items-center justify-center min-h-[60vh]">
            <Button
              variant="ghost"
              size="icon"
              className="absolute top-3 right-3 z-10 text-white hover:bg-white/20"
              onClick={() => setSelectedIndex(null)}
            >
              <X className="h-5 w-5" />
            </Button>
            {selectedIndex !== null && (
              <img
                src={getDisplayUrl(whiteboards[selectedIndex]) || ''}
                alt={getLabel(whiteboards[selectedIndex])}
                className="max-w-full max-h-[80vh] object-contain"
              />
            )}
          </div>
          {selectedIndex !== null && (
            <div className="p-3 text-center space-y-1">
              <Badge variant="outline" className="text-xs text-white/60 border-white/20">
                {whiteboards[selectedIndex].entry_type === 'drawing' ? 'Drawing' : 'Whiteboard Photo'}
              </Badge>
              <p className="text-sm text-white/80">{getLabel(whiteboards[selectedIndex])}</p>
            </div>
          )}
        </DialogContent>
      </Dialog>
    </>
  )
}
