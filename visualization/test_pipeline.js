/**
 * Test script for the visualization pipeline
 * Run with: node test_pipeline.js
 */

const FAL_API_KEY = "75a7a308-5810-4e9d-91a6-7eba36de83a5:f9c93ec0539a9da27cd881c0781bcfc7";

const TEST_IMAGE_URL = "https://wnyrnpeabhxdqvcpofmb.supabase.co/storage/v1/object/public/scans/qnexwr/visualization_1764994833_22E51816.jpg";

const ENDPOINTS = {
  evfSam: 'https://queue.fal.run/fal-ai/evf-sam',
  depthAnything: 'https://queue.fal.run/fal-ai/image-preprocessors/depth-anything/v2',
  fluxFill: 'https://queue.fal.run/fal-ai/flux-pro/v1/fill'
};

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

async function falApiCall(endpoint, payload, operationName) {
  console.log(`\n📍 ${operationName}: Starting...`);
  console.log(`   Payload:`, JSON.stringify(payload, null, 2));

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
  console.log(`   Submission response:`, JSON.stringify(submission, null, 2));

  // If result is immediate (sync mode)
  if (submission.images || submission.image || submission.depth_map) {
    console.log(`✅ ${operationName}: Complete (immediate)`);
    return submission;
  }

  // Poll for result - use URLs from the submission response
  const statusUrl = submission.status_url;
  const resultUrl = submission.response_url;

  console.log(`   Polling for result... (request_id: ${submission.request_id})`);
  console.log(`   Status URL: ${statusUrl}`);
  console.log(`   Result URL: ${resultUrl}`);

  const maxPolls = 90;
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
      console.log(`   Status response (non-JSON): ${statusText.substring(0, 200)}`);
      continue;
    }

    if (status.status === 'COMPLETED') {
      const resultResponse = await fetch(resultUrl, {
        headers: { 'Authorization': `Key ${FAL_API_KEY}` }
      });
      const resultText = await resultResponse.text();
      let result;
      try {
        result = JSON.parse(resultText);
      } catch (e) {
        console.log(`   Result response (non-JSON): ${resultText.substring(0, 200)}`);
        throw new Error('Failed to parse result JSON');
      }
      console.log(`✅ ${operationName}: Complete`);
      console.log(`   Result:`, JSON.stringify(result, null, 2));
      return result;
    }

    if (status.status === 'FAILED') {
      throw new Error(status.error || 'Processing failed');
    }

    if (poll % 5 === 0) {
      console.log(`   Still processing... (${poll * 2}s, status: ${status.status})`);
    }
  }

  throw new Error('Timeout waiting for result');
}

async function testMaskGeneration() {
  console.log('='.repeat(60));
  console.log('Testing Mask Generation with EVF-SAM');
  console.log('='.repeat(60));
  console.log(`\nImage URL: ${TEST_IMAGE_URL}`);

  const maskPrompts = {
    cabinets: "all kitchen cabinets, cabinet doors, cabinet drawers, cabinet frames, cabinet hardware",
    countertop: "kitchen countertop surface, counter top, kitchen counter",
    backsplash: "kitchen backsplash, tile wall between countertop and upper cabinets, backsplash area"
  };

  // Test cabinet mask first
  try {
    const cabinetResult = await falApiCall(ENDPOINTS.evfSam, {
      image_url: TEST_IMAGE_URL,
      prompt: maskPrompts.cabinets
    }, 'Cabinet Mask');

    console.log('\n🎉 Cabinet mask URL:', cabinetResult.image?.url);

    // Test countertop mask
    const countertopResult = await falApiCall(ENDPOINTS.evfSam, {
      image_url: TEST_IMAGE_URL,
      prompt: maskPrompts.countertop
    }, 'Countertop Mask');

    console.log('\n🎉 Countertop mask URL:', countertopResult.image?.url);

    // Test backsplash mask
    const backsplashResult = await falApiCall(ENDPOINTS.evfSam, {
      image_url: TEST_IMAGE_URL,
      prompt: maskPrompts.backsplash
    }, 'Backsplash Mask');

    console.log('\n🎉 Backsplash mask URL:', backsplashResult.image?.url);

    return {
      cabinets: cabinetResult.image?.url,
      countertop: countertopResult.image?.url,
      backsplash: backsplashResult.image?.url
    };

  } catch (error) {
    console.error('\n❌ Error:', error.message);
    throw error;
  }
}

async function testDepthMap() {
  console.log('\n' + '='.repeat(60));
  console.log('Testing Depth Map Generation');
  console.log('='.repeat(60));

  try {
    const result = await falApiCall(ENDPOINTS.depthAnything, {
      image_url: TEST_IMAGE_URL
    }, 'Depth Map');

    console.log('\n🎉 Depth map URL:', result.image?.url);
    return result.image?.url;

  } catch (error) {
    console.error('\n❌ Error:', error.message);
    throw error;
  }
}

async function testInpainting(maskUrl) {
  console.log('\n' + '='.repeat(60));
  console.log('Testing Inpainting with Flux Fill');
  console.log('='.repeat(60));

  const prompt = "white wood shaker style kitchen cabinets, beautiful cabinet doors with elegant hardware, high-end kitchen design, photorealistic, professional photography lighting, 8k resolution";

  try {
    const result = await falApiCall(ENDPOINTS.fluxFill, {
      image_url: TEST_IMAGE_URL,
      mask_url: maskUrl,
      prompt: prompt,
      num_images: 1,
      safety_tolerance: 2,
      output_format: 'jpeg'
    }, 'Cabinet Inpainting');

    console.log('\n🎉 Inpainted image URL:', result.images?.[0]?.url);
    return result.images?.[0]?.url;

  } catch (error) {
    console.error('\n❌ Error:', error.message);
    throw error;
  }
}

async function main() {
  console.log('\n🚀 Starting Visualization Pipeline Test\n');

  // Use previously generated masks to save time/cost
  const existingMasks = {
    cabinets: 'https://fal.media/files/elephant/XDbd3WOCL6QuYIHRhrZo__f2a582efe59e4081a8ce91588b371af3.png',
    countertop: 'https://fal.media/files/zebra/lmAg2UVd051lgJpUTgH-I_847913dbd16f49c1aba999f5ff3566de.png',
    backsplash: 'https://fal.media/files/zebra/aDalWb6GQCdXYgQcHfRdL_7e8969c3cf5244389bf93f4dab14a94a.png'
  };

  const skipMaskGeneration = true; // Set to false to regenerate masks

  try {
    let masks;
    if (skipMaskGeneration) {
      console.log('Using existing masks...');
      masks = existingMasks;
    } else {
      // Step 1: Generate masks
      masks = await testMaskGeneration();
    }

    // Step 2: Generate depth map (optional, for reference)
    // const depthMapUrl = await testDepthMap();

    // Step 3: Test inpainting with cabinet mask
    if (masks.cabinets) {
      const inpaintedUrl = await testInpainting(masks.cabinets);
      console.log('\n🎉 Final inpainted image:', inpaintedUrl);
    }

    console.log('\n' + '='.repeat(60));
    console.log('✅ ALL TESTS COMPLETED SUCCESSFULLY');
    console.log('='.repeat(60));

  } catch (error) {
    console.error('\n❌ TEST FAILED:', error.message);
    process.exit(1);
  }
}

main();
