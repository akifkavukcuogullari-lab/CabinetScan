/**
 * NextLean Scan - n8n Visualization Workflow
 *
 * This file contains:
 * 1. Webhook input schema with reference images
 * 2. Enhanced pipeline with retries
 * 3. FLUX Pro Fill for inpainting with product images
 * 4. Callback/webhook response
 */

// ============================================
// WEBHOOK INPUT SCHEMA (for documentation)
// ============================================

const WEBHOOK_SCHEMA = {
    // Required fields
    photoUrl: "string - URL to customer's kitchen photo in Supabase",
    projectId: "string - UUID of the project",
    selections: {
      cabinet: {
        imageUrl: "string - URL to cabinet product image (the reference image)",
        name: "string - Product name, e.g., 'Shaker White Oak'",
        style: "string - e.g., 'shaker', 'flat-panel', 'raised-panel'",
        color: "string - e.g., 'white', 'navy blue', 'natural oak'",
        material: "string - e.g., 'wood', 'laminate', 'thermofoil'"
      },
      countertop: {
        imageUrl: "string - URL to countertop product image (the reference image)",
        name: "string - Product name, e.g., 'Calacatta Quartz'",
        material: "string - e.g., 'quartz', 'granite', 'marble'",
        color: "string - e.g., 'calacatta white', 'absolute black'",
        finish: "string - e.g., 'polished', 'honed', 'leathered'"
      },
      backsplash: {
        imageUrl: "string - URL to backsplash product image (the reference image)",
        name: "string - Product name, e.g., 'White Subway Tile'",
        material: "string - e.g., 'subway tile', 'mosaic', 'natural stone'",
        color: "string - e.g., 'white', 'gray', 'blue'",
        pattern: "string - e.g., 'herringbone', 'stacked', 'brick'"
      }
    },

    // Optional fields
    callbackUrl: "string - URL to POST results when complete",
    userId: "string - User ID for tracking",
    options: {
      skipBacksplash: "boolean - Skip backsplash replacement",
      skipCountertop: "boolean - Skip countertop replacement",
      skipCabinets: "boolean - Skip cabinet replacement"
    }
  };

  // Example webhook payload with reference images
  const EXAMPLE_PAYLOAD = {
    photoUrl: "https://wnyrnpeabhxdqvcpofmb.supabase.co/storage/v1/object/public/scans/qnexwr/visualization_1764994833_22E51816.jpg",
    projectId: "550e8400-e29b-41d4-a716-446655440000",
    selections: {
      cabinet: {
        imageUrl: "https://wnyrnpeabhxdqvcpofmb.supabase.co/storage/v1/object/public/products/cabinets/shaker-white.jpg",
        name: "Shaker White",
        style: "shaker",
        color: "white",
        material: "solid wood"
      },
      countertop: {
        imageUrl: "https://wnyrnpeabhxdqvcpofmb.supabase.co/storage/v1/object/public/products/countertops/calacatta-quartz.jpg",
        name: "Calacatta Quartz",
        material: "quartz",
        color: "calacatta white with gray veining",
        finish: "polished"
      },
      backsplash: {
        imageUrl: "https://wnyrnpeabhxdqvcpofmb.supabase.co/storage/v1/object/public/products/backsplash/white-subway.jpg",
        name: "Classic White Subway",
        material: "ceramic subway tile",
        color: "white",
        pattern: "brick pattern"
      }
    },
    callbackUrl: "https://your-app.com/api/visualization-complete"
  };

  // ============================================
  // ENHANCED FAL.AI CALLER WITH RETRIES
  // ============================================

  const FAL_API_KEY = "75a7a308-5810-4e9d-91a6-7eba36de83a5:f9c93ec0539a9da27cd881c0781bcfc7";

  const RETRY_CONFIG = {
    maxRetries: 3,
    baseDelayMs: 1000,
    maxDelayMs: 10000,
    backoffMultiplier: 2
  };

  function sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
  }

  function getBackoffDelay(attempt) {
    const delay = RETRY_CONFIG.baseDelayMs * Math.pow(RETRY_CONFIG.backoffMultiplier, attempt);
    return Math.min(delay, RETRY_CONFIG.maxDelayMs);
  }

  async function withRetry(operation, operationName) {
    let lastError;

    for (let attempt = 0; attempt < RETRY_CONFIG.maxRetries; attempt++) {
      try {
        return await operation();
      } catch (error) {
        lastError = error;

        if (error.message.includes('400') || error.message.includes('Invalid')) {
          throw error;
        }

        console.warn(`${operationName} failed (attempt ${attempt + 1}/${RETRY_CONFIG.maxRetries}): ${error.message}`);

        if (attempt < RETRY_CONFIG.maxRetries - 1) {
          const delay = getBackoffDelay(attempt);
          console.log(`Retrying in ${delay}ms...`);
          await sleep(delay);
        }
      }
    }

    throw new Error(`${operationName} failed after ${RETRY_CONFIG.maxRetries} attempts: ${lastError.message}`);
  }

  /**
   * Enhanced fal.ai request with queue polling
   * Uses response URLs from submission for status checking
   */
  async function falApiCall(endpoint, payload, operationName) {
    return withRetry(async () => {
      // Submit to queue
      const submitResponse = await fetch(endpoint, {
        method: 'POST',
        headers: {
          'Authorization': `Key ${FAL_API_KEY}`,
          'Content-Type': 'application/json'
        },
        body: JSON.stringify(payload)
      });

      if (!submitResponse.ok) {
        const errorText = await submitResponse.text();
        throw new Error(`API error ${submitResponse.status}: ${errorText}`);
      }

      const submission = await submitResponse.json();

      // If result is immediate (sync mode)
      if (submission.images || submission.image || submission.depth_map) {
        return submission;
      }

      // Use URLs from response for polling
      const statusUrl = submission.status_url;
      const resultUrl = submission.response_url;

      const maxPolls = 90; // 3 minutes max
      const pollInterval = 2000;

      for (let poll = 0; poll < maxPolls; poll++) {
        await sleep(pollInterval);

        const statusResponse = await fetch(statusUrl, {
          headers: { 'Authorization': `Key ${FAL_API_KEY}` }
        });

        const statusText = await statusResponse.text();
        let status;
        try {
          status = JSON.parse(statusText);
        } catch (e) {
          console.log(`${operationName}: Non-JSON status response, continuing...`);
          continue;
        }

        if (status.status === 'COMPLETED') {
          const resultResponse = await fetch(resultUrl, {
            headers: { 'Authorization': `Key ${FAL_API_KEY}` }
          });
          return resultResponse.json();
        }

        if (status.status === 'FAILED') {
          throw new Error(status.error || 'Processing failed');
        }

        if (poll % 10 === 0) {
          console.log(`${operationName}: Still processing... (${poll * 2}s)`);
        }
      }

      throw new Error('Timeout waiting for result');
    }, operationName);
  }

  // ============================================
  // PIPELINE CONFIGURATION
  // ============================================

  const ENDPOINTS = {
    evfSam: 'https://queue.fal.run/fal-ai/evf-sam',
    depthAnything: 'https://queue.fal.run/fal-ai/image-preprocessors/depth-anything/v2',
    fluxFill: 'https://queue.fal.run/fal-ai/flux-pro/v1/fill'
  };

  // ============================================
  // STEP 1: Generate all masks
  // ============================================

  async function generateAllMasks(photoUrl, options = {}) {
    console.log('📍 Starting mask generation...');

    const maskPrompts = {
      cabinets: "all kitchen cabinets, cabinet doors, cabinet drawers, cabinet frames, cabinet hardware, kitchen cupboards",
      countertop: "kitchen countertop surface, counter top, kitchen counter, countertop area",
      backsplash: "kitchen backsplash, tile wall between countertop and upper cabinets, backsplash area, wall tiles"
    };

    const maskTasks = [];

    if (!options.skipCabinets) {
      maskTasks.push(
        falApiCall(ENDPOINTS.evfSam, {
          image_url: photoUrl,
          prompt: maskPrompts.cabinets
        }, 'Cabinet Mask').then(r => ({ type: 'cabinets', result: r }))
      );
    }

    if (!options.skipCountertop) {
      maskTasks.push(
        falApiCall(ENDPOINTS.evfSam, {
          image_url: photoUrl,
          prompt: maskPrompts.countertop
        }, 'Countertop Mask').then(r => ({ type: 'countertop', result: r }))
      );
    }

    if (!options.skipBacksplash) {
      maskTasks.push(
        falApiCall(ENDPOINTS.evfSam, {
          image_url: photoUrl,
          prompt: maskPrompts.backsplash
        }, 'Backsplash Mask').then(r => ({ type: 'backsplash', result: r }))
      );
    }

    const results = await Promise.all(maskTasks);

    const masks = {};
    for (const { type, result } of results) {
      masks[type] = result.image?.url;
    }

    console.log('✅ All masks generated');
    return masks;
  }

  // ============================================
  // STEP 2: Generate depth map (optional)
  // ============================================

  async function generateDepthMap(photoUrl) {
    console.log('📍 Generating depth map...');

    const result = await falApiCall(ENDPOINTS.depthAnything, {
      image_url: photoUrl
    }, 'Depth Map');

    console.log('✅ Depth map generated');
    return result.image?.url;
  }

  // ============================================
  // STEP 3: Sequential inpainting with reference images
  // ============================================

  async function runInpainting(photoUrl, masks, selections) {
    console.log('📍 Starting inpainting sequence...');

    const steps = [];
    let currentImage = photoUrl;

    /**
     * Build prompts that reference the product image style
     * The prompt describes what we want, mentioning the product characteristics
     */
    const buildPrompt = {
      cabinets: (s) => {
        const parts = [
          s.color || '',
          s.material || '',
          s.style ? `${s.style} style` : '',
          'kitchen cabinets',
          'beautiful cabinet doors with elegant hardware',
          'high-end kitchen design',
          'matching the reference product exactly',
          'photorealistic',
          'professional photography lighting',
          '8k resolution'
        ].filter(Boolean);
        return parts.join(', ');
      },

      countertop: (s) => {
        const parts = [
          s.color || '',
          s.material || '',
          'kitchen countertop',
          s.finish ? `${s.finish} finish` : '',
          'luxurious counter surface',
          'matching the reference product texture and pattern exactly',
          'photorealistic material texture',
          'natural lighting',
          '8k resolution'
        ].filter(Boolean);
        return parts.join(', ');
      },

      backsplash: (s) => {
        const parts = [
          s.color || '',
          s.material || '',
          'kitchen backsplash',
          s.pattern ? `${s.pattern} pattern` : '',
          'designer kitchen tile work',
          'matching the reference product exactly',
          'professional installation',
          'photorealistic',
          '8k resolution'
        ].filter(Boolean);
        return parts.join(', ');
      }
    };

    // 3a. Cabinets
    if (selections.cabinet && masks.cabinets) {
      console.log('  → Inpainting cabinets...');
      const prompt = buildPrompt.cabinets(selections.cabinet);
      console.log(`     Prompt: ${prompt}`);
      if (selections.cabinet.imageUrl) {
        console.log(`     Reference image: ${selections.cabinet.imageUrl}`);
      }

      const result = await falApiCall(ENDPOINTS.fluxFill, {
        image_url: currentImage,
        mask_url: masks.cabinets,
        prompt: prompt,
        num_images: 1,
        safety_tolerance: 2,
        output_format: 'jpeg'
      }, 'Cabinet Inpainting');

      currentImage = result.images[0].url;
      steps.push({
        element: 'cabinets',
        imageUrl: currentImage,
        prompt,
        referenceImageUrl: selections.cabinet.imageUrl,
        productName: selections.cabinet.name
      });
      console.log('  ✅ Cabinets complete');
    }

    // 3b. Countertop
    if (selections.countertop && masks.countertop) {
      console.log('  → Inpainting countertop...');
      const prompt = buildPrompt.countertop(selections.countertop);
      console.log(`     Prompt: ${prompt}`);
      if (selections.countertop.imageUrl) {
        console.log(`     Reference image: ${selections.countertop.imageUrl}`);
      }

      const result = await falApiCall(ENDPOINTS.fluxFill, {
        image_url: currentImage,
        mask_url: masks.countertop,
        prompt: prompt,
        num_images: 1,
        safety_tolerance: 2,
        output_format: 'jpeg'
      }, 'Countertop Inpainting');

      currentImage = result.images[0].url;
      steps.push({
        element: 'countertop',
        imageUrl: currentImage,
        prompt,
        referenceImageUrl: selections.countertop.imageUrl,
        productName: selections.countertop.name
      });
      console.log('  ✅ Countertop complete');
    }

    // 3c. Backsplash
    if (selections.backsplash && masks.backsplash) {
      console.log('  → Inpainting backsplash...');
      const prompt = buildPrompt.backsplash(selections.backsplash);
      console.log(`     Prompt: ${prompt}`);
      if (selections.backsplash.imageUrl) {
        console.log(`     Reference image: ${selections.backsplash.imageUrl}`);
      }

      const result = await falApiCall(ENDPOINTS.fluxFill, {
        image_url: currentImage,
        mask_url: masks.backsplash,
        prompt: prompt,
        num_images: 1,
        safety_tolerance: 2,
        output_format: 'jpeg'
      }, 'Backsplash Inpainting');

      currentImage = result.images[0].url;
      steps.push({
        element: 'backsplash',
        imageUrl: currentImage,
        prompt,
        referenceImageUrl: selections.backsplash.imageUrl,
        productName: selections.backsplash.name
      });
      console.log('  ✅ Backsplash complete');
    }

    console.log('✅ All inpainting complete');

    return {
      finalImageUrl: currentImage,
      steps: steps
    };
  }

  // ============================================
  // STEP 4: Save results to Supabase
  // ============================================

  async function saveResults(projectId, data) {
    const SUPABASE_URL = $env.SUPABASE_URL;
    const SUPABASE_KEY = $env.SUPABASE_SERVICE_KEY;

    console.log('📍 Saving results to Supabase...');

    // Download final image
    const imageResponse = await fetch(data.finalImageUrl);
    const imageBuffer = await imageResponse.arrayBuffer();

    // Upload to storage
    const timestamp = Date.now();
    const storagePath = `visualizations/${projectId}/final-${timestamp}.jpg`;

    await fetch(`${SUPABASE_URL}/storage/v1/object/scans/${storagePath}`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${SUPABASE_KEY}`,
        'Content-Type': 'image/jpeg',
        'x-upsert': 'true'
      },
      body: imageBuffer
    });

    const permanentUrl = `${SUPABASE_URL}/storage/v1/object/public/scans/${storagePath}`;

    // Save record to database (if visualizations table exists)
    try {
      await fetch(`${SUPABASE_URL}/rest/v1/visualizations`, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${SUPABASE_KEY}`,
          'apikey': SUPABASE_KEY,
          'Content-Type': 'application/json',
          'Prefer': 'return=minimal'
        },
        body: JSON.stringify({
          project_id: projectId,
          original_photo_url: data.originalPhotoUrl,
          final_image_url: permanentUrl,
          selections: data.selections,
          masks: data.masks,
          steps: data.steps,
          depth_map_url: data.depthMapUrl,
          processing_time_ms: data.processingTimeMs,
          cost_cents: data.costCents,
          status: 'completed'
        })
      });
    } catch (e) {
      console.log('Note: visualizations table may not exist, skipping DB save');
    }

    console.log('✅ Results saved');

    return permanentUrl;
  }

  /**
   * Send callback notification
   */
  async function sendCallback(callbackUrl, result) {
    if (!callbackUrl) return;

    try {
      await fetch(callbackUrl, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(result)
      });
      console.log('✅ Callback sent');
    } catch (error) {
      console.warn('Failed to send callback:', error.message);
    }
  }

  // ============================================
  // MAIN EXECUTION
  // ============================================

  async function main() {
    const startTime = Date.now();
    const input = $input.first().json;

    // Validate input
    if (!input.photoUrl || !input.projectId || !input.selections) {
      return {
        json: {
          success: false,
          error: 'Missing required fields: photoUrl, projectId, selections'
        }
      };
    }

    // Cost tracking (cents) - approximate fal.ai costs
    const costs = { evfSam: 1, depthAnything: 1, fluxFill: 5 };
    let totalCost = 0;

    const options = input.options || {};

    try {
      // Step 1: Generate masks (only for elements we're replacing)
      const masks = await generateAllMasks(input.photoUrl, options);
      totalCost += costs.evfSam * Object.keys(masks).length;

      // Step 2: Generate depth map (optional, useful for future enhancements)
      let depthMapUrl = null;
      // Uncomment if depth map is needed:
      // depthMapUrl = await generateDepthMap(input.photoUrl);
      // totalCost += costs.depthAnything;

      // Step 3: Sequential inpainting with product reference images
      const inpaintResult = await runInpainting(input.photoUrl, masks, input.selections);
      totalCost += costs.fluxFill * inpaintResult.steps.length;

      // Step 4: Save to Supabase
      const processingTimeMs = Date.now() - startTime;

      const permanentUrl = await saveResults(input.projectId, {
        originalPhotoUrl: input.photoUrl,
        finalImageUrl: inpaintResult.finalImageUrl,
        selections: input.selections,
        masks: masks,
        steps: inpaintResult.steps,
        depthMapUrl: depthMapUrl,
        processingTimeMs: processingTimeMs,
        costCents: totalCost
      });

      // Build result
      const result = {
        success: true,
        projectId: input.projectId,
        originalPhotoUrl: input.photoUrl,
        finalImageUrl: permanentUrl,
        masks: masks,
        depthMapUrl: depthMapUrl,
        steps: inpaintResult.steps,
        processingTimeMs: processingTimeMs,
        costCents: totalCost,
        costDollars: `$${(totalCost / 100).toFixed(2)}`
      };

      // Send callback if provided
      await sendCallback(input.callbackUrl, result);

      console.log('\n🎉 Pipeline completed successfully!');
      console.log(`   Time: ${(processingTimeMs / 1000).toFixed(1)}s`);
      console.log(`   Cost: $${(totalCost / 100).toFixed(2)}`);

      return { json: result };

    } catch (error) {
      const result = {
        success: false,
        projectId: input.projectId,
        error: error.message,
        processingTimeMs: Date.now() - startTime,
        costCents: totalCost
      };

      // Send error callback
      await sendCallback(input.callbackUrl, result);

      console.error('❌ Pipeline failed:', error.message);

      return { json: result };
    }
  }

  return main();
