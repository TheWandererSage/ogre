/*
-----------------------------------------------------------------------------
This source file is part of OGRE
    (Object-oriented Graphics Rendering Engine)
For the latest info, see http://www.ogre3d.org/

Copyright (c) 2000-2009 Torus Knot Software Ltd

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
-----------------------------------------------------------------------------
*/

#include "OgreEAGLES2Context.h"
#include "OgreGLES2RenderSystem.h"
#include "OgreRoot.h"

// TODO: DJR - Add support for EAGLSharegroups if deemed necessary
namespace Ogre {
    EAGLES2Context::EAGLES2Context(CAEAGLLayer *drawable)
        : 
        mBackingWidth(0),
        mBackingHeight(0),
        mViewRenderbuffer(0),
        mViewFramebuffer(0),
        mDepthRenderbuffer(0),
        mIsMultiSampleSupported(false),
        mNumSamples(0),
        mFSAAFramebuffer(0),
        mFSAARenderbuffer(0)
    {

        mDrawable = [drawable retain];

        mContext = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
        
        if (!mContext || ![EAGLContext setCurrentContext:mContext])
        {
            OGRE_EXCEPT(Exception::ERR_RENDERINGAPI_ERROR,
                        "Unable to create a suitable EAGLContext",
                        "EAGLES2Context::EAGLES2Context");
        }
    }

    EAGLES2Context::~EAGLES2Context()
    {
        GLES2RenderSystem *rs =
            static_cast<GLES2RenderSystem*>(Root::getSingleton().getRenderSystem());

        rs->_unregisterContext(this);

        destroyFramebuffer();

        if ([EAGLContext currentContext] == mContext)
        {
            [EAGLContext setCurrentContext:nil];
        }
        
        [mContext release];
        [mDrawable release];
    }

    bool EAGLES2Context::createFramebuffer()
    {
        destroyFramebuffer();

        glGenFramebuffers(1, &mViewFramebuffer);
        GL_CHECK_ERROR
        glGenRenderbuffers(1, &mViewRenderbuffer);
        GL_CHECK_ERROR
        
        glBindFramebuffer(GL_FRAMEBUFFER, mViewFramebuffer);
        GL_CHECK_ERROR
        glBindRenderbuffer(GL_RENDERBUFFER, mViewRenderbuffer);
        GL_CHECK_ERROR

        if(![mContext renderbufferStorage:GL_RENDERBUFFER fromDrawable:(id<EAGLDrawable>) mDrawable])
        {
            GL_CHECK_ERROR
            OGRE_EXCEPT(Exception::ERR_RENDERINGAPI_ERROR,
                        "Failed to bind the drawable to a renderbuffer object",
                        __FUNCTION__);
            return false;
        }

        glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH, &mBackingWidth);
        GL_CHECK_ERROR
        glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &mBackingHeight);
        GL_CHECK_ERROR
        glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, mViewRenderbuffer);
        GL_CHECK_ERROR



        #if GL_APPLE_framebuffer_multisample
        if(mIsMultiSampleSupported && mNumSamples > 0)
        {
            // Determine how many MSAS samples to use
            GLint maxSamplesAllowed;
            glGetIntegerv(GL_MAX_SAMPLES_APPLE, &maxSamplesAllowed);
            int samplesToUse = (mNumSamples > maxSamplesAllowed) ? maxSamplesAllowed : mNumSamples;
            
            // Create the FSAA framebuffer (offscreen)
            glGenFramebuffers(1, &mFSAAFramebuffer);
            GL_CHECK_ERROR
            glBindFramebuffer(GL_FRAMEBUFFER, mFSAAFramebuffer);
            GL_CHECK_ERROR
            
            /* Create the offscreen MSAA color buffer.
             * After rendering, the contents of this will be blitted into mFSAAFramebuffer */
            glGenRenderbuffers(1, &mFSAARenderbuffer);
            GL_CHECK_ERROR
            glBindRenderbuffer(GL_RENDERBUFFER, mFSAARenderbuffer);
            GL_CHECK_ERROR
            glRenderbufferStorageMultisampleAPPLE(GL_RENDERBUFFER, samplesToUse, GL_RGBA8_OES, mBackingWidth, mBackingHeight);
            GL_CHECK_ERROR
            glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, mFSAARenderbuffer);
            GL_CHECK_ERROR
            
            // Create the FSAA depth buffer
            glGenRenderbuffers(1, &mDepthRenderbuffer);
            GL_CHECK_ERROR
            glBindRenderbuffer(GL_RENDERBUFFER, mDepthRenderbuffer);
            GL_CHECK_ERROR
            glRenderbufferStorageMultisampleAPPLE(GL_RENDERBUFFER, samplesToUse, GL_DEPTH_COMPONENT24_OES, mBackingWidth, mBackingHeight);
            GL_CHECK_ERROR
            glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, mDepthRenderbuffer);
            GL_CHECK_ERROR

            // Validate the FSAA framebuffer
            if(glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE)
            {
                GL_CHECK_ERROR
                OGRE_EXCEPT(Exception::ERR_RENDERINGAPI_ERROR,
                            "Failed to make complete FSAA framebuffer object",
                            __FUNCTION__);
                return false;
            }
        }
        else
#endif
        {
            glGenRenderbuffers(1, &mDepthRenderbuffer);
            GL_CHECK_ERROR
            glBindRenderbuffer(GL_RENDERBUFFER, mDepthRenderbuffer);
            GL_CHECK_ERROR
            glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT16, mBackingWidth, mBackingHeight);
            GL_CHECK_ERROR
            glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, mDepthRenderbuffer);
            GL_CHECK_ERROR
        }

        glBindFramebuffer(GL_FRAMEBUFFER, mViewFramebuffer);
        if(glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE)
        {
            GL_CHECK_ERROR
            OGRE_EXCEPT(Exception::ERR_RENDERINGAPI_ERROR,
                        "Failed to make complete framebuffer object",
                        __FUNCTION__);
            return false;
        }

        return true;
    }

    void EAGLES2Context::destroyFramebuffer()
    {
        glDeleteFramebuffers(1, &mViewFramebuffer);
        mViewFramebuffer = 0;
        glDeleteRenderbuffers(1, &mViewRenderbuffer);
        mViewRenderbuffer = 0;
        
        if(mFSAARenderbuffer)
        {
            glDeleteRenderbuffers(1, &mFSAARenderbuffer);
            mFSAARenderbuffer = 0;
        }

        if(mFSAAFramebuffer)
        {
            glDeleteFramebuffers(1, &mFSAAFramebuffer);
            mFSAAFramebuffer = 0;
        }
        
        if(mDepthRenderbuffer)
        {
            glDeleteRenderbuffers(1, &mDepthRenderbuffer);
            mDepthRenderbuffer = 0;
        }
    }

    void EAGLES2Context::setCurrent()
    {
        GLboolean ret = [EAGLContext setCurrentContext:mContext];
        if (!ret)
        {
            OGRE_EXCEPT(Exception::ERR_RENDERINGAPI_ERROR,
                        "Fail to make context current",
                        __FUNCTION__);
        }
    }

    void EAGLES2Context::endCurrent()
    {
        // Do nothing
    }

    GLES2Context * EAGLES2Context::clone() const
    {
        return const_cast<EAGLES2Context *>(this);
    }

	CAEAGLLayer * EAGLES2Context::getDrawable() const
	{
		return mDrawable;
	}

	EAGLContext * EAGLES2Context::getContext() const
	{
		return mContext;
	}
}
