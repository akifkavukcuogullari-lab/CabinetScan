'use client'

import { useRef, useEffect, useImperativeHandle, forwardRef } from 'react'
import { OrbitControls as DreiOrbitControls } from '@react-three/drei'
import { useThree } from '@react-three/fiber'
import * as THREE from 'three'
import type { OrbitControls as OrbitControlsImpl } from 'three-stdlib'

export interface ControlsRef {
  reset: () => void
  zoomIn: () => void
  zoomOut: () => void
}

interface ControlsProps {
  autoRotate?: boolean
  autoRotateSpeed?: number
  enableDamping?: boolean
  dampingFactor?: number
  minDistance?: number
  maxDistance?: number
  minPolarAngle?: number
  maxPolarAngle?: number
  onControlsChange?: () => void
}

export const Controls = forwardRef<ControlsRef, ControlsProps>(
  function Controls(
    {
      autoRotate = false,
      autoRotateSpeed = 1,
      enableDamping = true,
      dampingFactor = 0.05,
      minDistance = 1,
      maxDistance = 50,
      minPolarAngle = 0,
      maxPolarAngle = Math.PI * 0.85,
      onControlsChange
    },
    ref
  ) {
    const controlsRef = useRef<OrbitControlsImpl>(null)
    const { camera, scene } = useThree()

    // Store initial camera position
    const initialPositionRef = useRef<THREE.Vector3 | null>(null)
    const initialTargetRef = useRef<THREE.Vector3 | null>(null)

    useEffect(() => {
      if (controlsRef.current && !initialPositionRef.current) {
        initialPositionRef.current = camera.position.clone()
        initialTargetRef.current = controlsRef.current.target.clone()
      }
    }, [camera])

    // Expose control methods
    useImperativeHandle(ref, () => ({
      reset: () => {
        if (controlsRef.current) {
          const controls = controlsRef.current

          // Calculate the center and size of the scene
          const box = new THREE.Box3().setFromObject(scene)
          const center = box.getCenter(new THREE.Vector3())
          const size = box.getSize(new THREE.Vector3())
          const maxDim = Math.max(size.x, size.y, size.z)

          // Reset target to center
          controls.target.copy(center)

          // Calculate optimal camera position
          const fov = (camera as THREE.PerspectiveCamera).fov * (Math.PI / 180)
          let cameraDistance = maxDim / (2 * Math.tan(fov / 2))
          cameraDistance *= 1.5

          // Animate to reset position
          const startPos = camera.position.clone()
          const endPos = new THREE.Vector3(
            center.x + cameraDistance * 0.7,
            center.y + cameraDistance * 0.5,
            center.z + cameraDistance * 0.7
          )

          // Simple animation
          let progress = 0
          const animate = () => {
            progress += 0.05
            if (progress >= 1) {
              camera.position.copy(endPos)
              controls.update()
              return
            }

            // Ease out cubic
            const t = 1 - Math.pow(1 - progress, 3)
            camera.position.lerpVectors(startPos, endPos, t)
            controls.update()
            requestAnimationFrame(animate)
          }
          animate()
        }
      },
      zoomIn: () => {
        if (controlsRef.current) {
          const controls = controlsRef.current
          const direction = new THREE.Vector3()
          direction.subVectors(controls.target, camera.position).normalize()

          // Move camera closer by 20%
          const distance = camera.position.distanceTo(controls.target)
          const newDistance = Math.max(distance * 0.8, minDistance)
          const newPosition = controls.target.clone().sub(
            direction.multiplyScalar(newDistance)
          )

          // Animate
          let progress = 0
          const startPos = camera.position.clone()
          const animate = () => {
            progress += 0.1
            if (progress >= 1) {
              camera.position.copy(newPosition)
              controls.update()
              return
            }
            const t = 1 - Math.pow(1 - progress, 3)
            camera.position.lerpVectors(startPos, newPosition, t)
            controls.update()
            requestAnimationFrame(animate)
          }
          animate()
        }
      },
      zoomOut: () => {
        if (controlsRef.current) {
          const controls = controlsRef.current
          const direction = new THREE.Vector3()
          direction.subVectors(controls.target, camera.position).normalize()

          // Move camera further by 20%
          const distance = camera.position.distanceTo(controls.target)
          const newDistance = Math.min(distance * 1.25, maxDistance)
          const newPosition = controls.target.clone().sub(
            direction.multiplyScalar(newDistance)
          )

          // Animate
          let progress = 0
          const startPos = camera.position.clone()
          const animate = () => {
            progress += 0.1
            if (progress >= 1) {
              camera.position.copy(newPosition)
              controls.update()
              return
            }
            const t = 1 - Math.pow(1 - progress, 3)
            camera.position.lerpVectors(startPos, newPosition, t)
            controls.update()
            requestAnimationFrame(animate)
          }
          animate()
        }
      }
    }), [camera, scene, minDistance, maxDistance])

    return (
      <DreiOrbitControls
        ref={controlsRef}
        makeDefault
        autoRotate={autoRotate}
        autoRotateSpeed={autoRotateSpeed}
        enableDamping={enableDamping}
        dampingFactor={dampingFactor}
        minDistance={minDistance}
        maxDistance={maxDistance}
        minPolarAngle={minPolarAngle}
        maxPolarAngle={maxPolarAngle}
        enablePan={true}
        panSpeed={0.8}
        rotateSpeed={0.8}
        zoomSpeed={1}
        onChange={onControlsChange}
      />
    )
  }
)
