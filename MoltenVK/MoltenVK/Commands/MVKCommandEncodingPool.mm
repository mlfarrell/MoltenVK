/*
 * MVKCommandEncodingPool.mm
 *
 * Copyright (c) 2014-2018 The Brenwill Workshop Ltd. (http://www.brenwill.com)
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 * 
 *     http://www.apache.org/licenses/LICENSE-2.0
 * 
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#include "MVKCommandEncodingPool.h"
#include "MVKImage.h"

using namespace std;

#pragma mark -
#pragma mark MVKCommandEncodingPool

// In order to provide thread-safety with minimal performance impact, each of these access
// functions follows a 3-step pattern:
//
// 1) Retrieve resource without locking, and if it exists, return it.
// 2) If it doesn't exist, lock, then test again if it exists, and if it does, return it.
// 3) If it still does not exist, create and cache the resource, and return it.
//
// Step 1 handles the common case where the resource exists, without the expense of a lock.
// Step 2 guards against a potential race condition where two threads get past Step 1 at
// the same time, and then both barrel ahead onto Step 3.
#define MVK_ENC_REZ_ACCESS(rezAccess, rezFactoryFunc)				\
	auto rez = rezAccess;											\
	if (rez) { return rez; }										\
																	\
	lock_guard<mutex> lock(_lock);									\
	rez = rezAccess;												\
	if (rez) { return rez; }										\
																	\
	rez = _device->getCommandResourceFactory()->rezFactoryFunc;		\
	rezAccess = rez;												\
	return rez


id<MTLRenderPipelineState> MVKCommandEncodingPool::getCmdClearMTLRenderPipelineState(MVKRPSKeyClearAtt& attKey) {
	MVK_ENC_REZ_ACCESS(_cmdClearMTLRenderPipelineStates[attKey], newCmdClearMTLRenderPipelineState(attKey));
}

id<MTLRenderPipelineState> MVKCommandEncodingPool::getCmdBlitImageMTLRenderPipelineState(MVKRPSKeyBlitImg& blitKey) {
	MVK_ENC_REZ_ACCESS(_cmdBlitImageMTLRenderPipelineStates[blitKey], newCmdBlitImageMTLRenderPipelineState(blitKey));
}

id<MTLSamplerState> MVKCommandEncodingPool::getCmdBlitImageMTLSamplerState(MTLSamplerMinMagFilter mtlFilter) {
    switch (mtlFilter) {
		case MTLSamplerMinMagFilterNearest: {
			MVK_ENC_REZ_ACCESS(_cmdBlitImageNearestMTLSamplerState, newCmdBlitImageMTLSamplerState(mtlFilter));
		}

		case MTLSamplerMinMagFilterLinear: {
			MVK_ENC_REZ_ACCESS(_cmdBlitImageLinearMTLSamplerState, newCmdBlitImageMTLSamplerState(mtlFilter));
		}
    }
}

id<MTLDepthStencilState> MVKCommandEncodingPool::getMTLDepthStencilState(bool useDepth, bool useStencil) {

    if (useDepth && useStencil) {
		MVK_ENC_REZ_ACCESS(_cmdClearDepthAndStencilDepthStencilState, newMTLDepthStencilState(useDepth, useStencil));
    }

    if (useDepth) {
		MVK_ENC_REZ_ACCESS(_cmdClearDepthOnlyDepthStencilState, newMTLDepthStencilState(useDepth, useStencil));
    }

    if (useStencil) {
		MVK_ENC_REZ_ACCESS(_cmdClearStencilOnlyDepthStencilState, newMTLDepthStencilState(useDepth, useStencil));
    }

	MVK_ENC_REZ_ACCESS(_cmdClearDefaultDepthStencilState, newMTLDepthStencilState(useDepth, useStencil));
}

const MVKMTLBufferAllocation* MVKCommandEncodingPool::acquireMTLBufferAllocation(NSUInteger length) {
    return _mtlBufferAllocator.acquireMTLBufferRegion(length);
}


id<MTLDepthStencilState> MVKCommandEncodingPool::getMTLDepthStencilState(MVKMTLDepthStencilDescriptorData& dsData) {
	MVK_ENC_REZ_ACCESS(_mtlDepthStencilStates[dsData], newMTLDepthStencilState(dsData));
}

MVKImage* MVKCommandEncodingPool::getTransferMVKImage(MVKImageDescriptorData& imgData) {
	MVK_ENC_REZ_ACCESS(_transferImages[imgData], newMVKImage(imgData));
}

id<MTLComputePipelineState> MVKCommandEncodingPool::getCmdCopyBufferBytesMTLComputePipelineState() {
	MVK_ENC_REZ_ACCESS(_mtlCopyBufferBytesComputePipelineState, newCmdCopyBufferBytesMTLComputePipelineState());
}

id<MTLComputePipelineState> MVKCommandEncodingPool::getCmdFillBufferMTLComputePipelineState() {
	MVK_ENC_REZ_ACCESS(_mtlFillBufferComputePipelineState, newCmdFillBufferMTLComputePipelineState());
}

void MVKCommandEncodingPool::clear() {
	lock_guard<mutex> lock(_lock);
	destroyMetalResources();
}


#pragma mark Construction

MVKCommandEncodingPool::MVKCommandEncodingPool(MVKDevice* device) : MVKBaseDeviceObject(device),
    _mtlBufferAllocator(device, device->_pMetalFeatures->maxMTLBufferSize, true) {
}

MVKCommandEncodingPool::~MVKCommandEncodingPool() {
	destroyMetalResources();
}

/**  Ensure all cached Metal components are released. */
void MVKCommandEncodingPool::destroyMetalResources() {
    for (auto& pair : _cmdBlitImageMTLRenderPipelineStates) { [pair.second release]; }
    _cmdBlitImageMTLRenderPipelineStates.clear();

    for (auto& pair : _cmdClearMTLRenderPipelineStates) { [pair.second release]; }
    _cmdClearMTLRenderPipelineStates.clear();

    for (auto& pair : _mtlDepthStencilStates) { [pair.second release]; }
    _mtlDepthStencilStates.clear();

    for (auto& pair : _transferImages) { _device->destroyImage(pair.second, nullptr); }
    _transferImages.clear();

    [_cmdBlitImageLinearMTLSamplerState release];
    _cmdBlitImageLinearMTLSamplerState = nil;

    [_cmdBlitImageNearestMTLSamplerState release];
    _cmdBlitImageNearestMTLSamplerState = nil;

    [_cmdClearDepthAndStencilDepthStencilState release];
    _cmdClearDepthAndStencilDepthStencilState = nil;

    [_cmdClearDepthOnlyDepthStencilState release];
    _cmdClearDepthOnlyDepthStencilState = nil;

    [_cmdClearStencilOnlyDepthStencilState release];
    _cmdClearStencilOnlyDepthStencilState = nil;

    [_cmdClearDefaultDepthStencilState release];
    _cmdClearDefaultDepthStencilState = nil;

    [_mtlCopyBufferBytesComputePipelineState release];
    _mtlCopyBufferBytesComputePipelineState = nil;
}

