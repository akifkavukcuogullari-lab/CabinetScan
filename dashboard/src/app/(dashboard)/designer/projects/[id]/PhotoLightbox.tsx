'use client'

import { useState } from 'react'
import {
  Dialog,
  DialogContent,
} from '@/components/ui/dialog'
import { X } from 'lucide-react'
import { Button } from '@/components/ui/button'

interface PhotoLightboxProps {
  photos: { url: string; label: string }[]
}

export function PhotoLightbox({ photos }: PhotoLightboxProps) {
  const [selectedIndex, setSelectedIndex] = useState<number | null>(null)

  return (
    <>
      <div className="grid grid-cols-2 sm:grid-cols-3 gap-3">
        {photos.map((photo, idx) => (
          <button
            key={idx}
            className="relative aspect-video rounded-lg overflow-hidden bg-gray-100 hover:ring-2 hover:ring-blue-400 transition-all cursor-pointer group"
            onClick={() => setSelectedIndex(idx)}
          >
            <img
              src={photo.url}
              alt={photo.label}
              className="w-full h-full object-cover group-hover:scale-105 transition-transform duration-200"
            />
            <div className="absolute bottom-0 inset-x-0 bg-gradient-to-t from-black/60 to-transparent p-2">
              <p className="text-xs text-white truncate">{photo.label}</p>
            </div>
          </button>
        ))}
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
                src={photos[selectedIndex].url}
                alt={photos[selectedIndex].label}
                className="max-w-full max-h-[80vh] object-contain"
              />
            )}
          </div>
          {selectedIndex !== null && (
            <div className="p-3 text-center">
              <p className="text-sm text-white/80">{photos[selectedIndex].label}</p>
            </div>
          )}
        </DialogContent>
      </Dialog>
    </>
  )
}
