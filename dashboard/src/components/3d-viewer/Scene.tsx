'use client'

import { useRef, useEffect, useMemo } from 'react'
import { useThree } from '@react-three/fiber'
import { useGLTF, Environment, ContactShadows, Center } from '@react-three/drei'
import * as THREE from 'three'

interface SceneProps {
  glbUrl: string
  onLoad?: () => void
  onError?: (error: Error) => void
  onProgress?: (progress: number) => void
}

// Model component that loads and displays the GLB
function Model({
  glbUrl,
  onLoad,
  onError
}: {
  glbUrl: string
  onLoad?: () => void
  onError?: (error: Error) => void
}) {
  const groupRef = useRef<THREE.Group>(null)

  // Load the GLB model
  const { scene } = useGLTF(glbUrl, true, true, (loader) => {
    loader.manager.onError = (url) => {
      console.error('Failed to load:', url)
      onError?.(new Error(`Failed to load model from ${url}`))
    }
  })

  // Clone the scene to avoid modifying the cached version
  const clonedScene = useMemo(() => {
    const clone = scene.clone()

    // Enable shadows on all meshes
    clone.traverse((child) => {
      if (child instanceof THREE.Mesh) {
        child.castShadow = true
        child.receiveShadow = true

        // Improve material quality
        if (child.material) {
          const material = child.material as THREE.MeshStandardMaterial
          if (material.isMeshStandardMaterial) {
            material.envMapIntensity = 1.2
            material.needsUpdate = true
          }
        }
      }
    })

    return clone
  }, [scene])

  // Notify when loaded
  useEffect(() => {
    onLoad?.()
  }, [onLoad])

  return (
    <Center>
      <primitive
        ref={groupRef}
        object={clonedScene}
        scale={1}
      />
    </Center>
  )
}

// Professional 3-point lighting setup
function Lighting() {
  return (
    <>
      {/* Ambient light for overall illumination */}
      <ambientLight intensity={0.4} color="#ffffff" />

      {/* Key light - main directional light with shadows */}
      <directionalLight
        position={[10, 10, 5]}
        intensity={1}
        castShadow
        shadow-mapSize={[2048, 2048]}
        shadow-camera-far={50}
        shadow-camera-left={-10}
        shadow-camera-right={10}
        shadow-camera-top={10}
        shadow-camera-bottom={-10}
        shadow-bias={-0.0001}
        color="#fff5e6"
      />

      {/* Fill light - softer, from opposite side */}
      <directionalLight
        position={[-8, 5, -5]}
        intensity={0.35}
        color="#e6f0ff"
      />

      {/* Rim light - from behind for edge definition */}
      <spotLight
        position={[0, 15, -10]}
        intensity={0.6}
        angle={0.5}
        penumbra={1}
        color="#ffffff"
      />

      {/* Bounce light from below */}
      <pointLight
        position={[0, -5, 0]}
        intensity={0.15}
        color="#f0f0ff"
      />
    </>
  )
}

// Ground plane with shadow
function Ground() {
  return (
    <ContactShadows
      position={[0, -0.01, 0]}
      opacity={0.5}
      scale={20}
      blur={2}
      far={10}
      resolution={256}
      color="#000000"
    />
  )
}

// Camera adjuster to fit model in view
function CameraController() {
  const { camera, scene } = useThree()

  useEffect(() => {
    // Calculate bounding box of the scene
    const box = new THREE.Box3().setFromObject(scene)
    const size = box.getSize(new THREE.Vector3())
    const center = box.getCenter(new THREE.Vector3())

    // Calculate distance to fit model in view
    const maxDim = Math.max(size.x, size.y, size.z)
    const fov = (camera as THREE.PerspectiveCamera).fov * (Math.PI / 180)
    let cameraDistance = maxDim / (2 * Math.tan(fov / 2))
    cameraDistance *= 1.5 // Add some padding

    // Position camera
    camera.position.set(
      center.x + cameraDistance * 0.7,
      center.y + cameraDistance * 0.5,
      center.z + cameraDistance * 0.7
    )
    camera.lookAt(center)
    camera.updateProjectionMatrix()
  }, [camera, scene])

  return null
}

export function Scene({ glbUrl, onLoad, onError }: SceneProps) {
  return (
    <>
      {/* Lighting setup */}
      <Lighting />

      {/* Environment map for reflections */}
      <Environment preset="city" />

      {/* Ground shadows */}
      <Ground />

      {/* Adjust camera to fit model */}
      <CameraController />

      {/* The 3D model */}
      <Model
        glbUrl={glbUrl}
        onLoad={onLoad}
        onError={onError}
      />
    </>
  )
}

// Preload function for better performance
export function preloadModel(url: string) {
  useGLTF.preload(url)
}
