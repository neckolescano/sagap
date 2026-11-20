package dev.sagap.sagap.ar

import android.content.Context
import android.opengl.GLES20
import android.opengl.GLSurfaceView
import android.view.Surface
import android.view.View
import com.google.ar.core.exceptions.CameraNotAvailableException
import com.google.ar.core.exceptions.SessionPausedException
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import javax.microedition.khronos.egl.EGLConfig
import javax.microedition.khronos.opengles.GL10

/** Camera preview + ARCore update loop, shown in Flutter via Hybrid Composition. */
class ArCameraView(context: Context, private val manager: ArSessionManager) :
    PlatformView, GLSurfaceView.Renderer {

    private val background = CameraBackgroundRenderer()

    private val glView = GLSurfaceView(context).apply {
        preserveEGLContextOnPause = true
        setEGLContextClientVersion(2)
        setEGLConfigChooser(8, 8, 8, 8, 16, 0)
        setRenderer(this@ArCameraView)
        renderMode = GLSurfaceView.RENDERMODE_CONTINUOUSLY
        // Start paused; the manager resumes it together with the session.
        onPause()
    }

    init {
        manager.attach(this)
    }

    override fun getView(): View = glView

    override fun dispose() = manager.detach(this)

    fun onResume() = glView.onResume()

    fun onPause() = glView.onPause()

    // ---- GLSurfaceView.Renderer (GL thread) -------------------------------

    override fun onSurfaceCreated(gl: GL10?, config: EGLConfig?) {
        GLES20.glClearColor(0f, 0f, 0f, 1f)
        background.createOnGlThread()
        manager.session?.setCameraTextureName(background.textureId)
    }

    override fun onSurfaceChanged(gl: GL10?, width: Int, height: Int) {
        GLES20.glViewport(0, 0, width, height)
        val rotation = glView.display?.rotation ?: Surface.ROTATION_0
        manager.session?.setDisplayGeometry(rotation, width, height)
    }

    override fun onDrawFrame(gl: GL10?) {
        GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT or GLES20.GL_DEPTH_BUFFER_BIT)
        val session = manager.session ?: return
        if (!manager.isRunning) return
        try {
            session.setCameraTextureName(background.textureId)
            val frame = session.update()
            background.draw(frame)
            manager.onFrame(frame)
        } catch (e: SessionPausedException) {
            // Paused between the isRunning check and update(); next frame is skipped too.
            return
        } catch (e: CameraNotAvailableException) {
            manager.onFrameError("camera_unavailable", "The camera stopped sending images")
        }
    }
}

class ArCameraViewFactory(private val manager: ArSessionManager) :
    PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    companion object {
        const val VIEW_TYPE = "sagap/ar_camera"
    }

    override fun create(context: Context, viewId: Int, args: Any?): PlatformView =
        ArCameraView(context, manager)
}
