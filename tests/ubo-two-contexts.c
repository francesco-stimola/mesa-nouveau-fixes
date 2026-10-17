/*
 * Reproducer for patch 0004 (nv50 constant buffer updates).
 *
 * One or two GLES 3.1 contexts, each with its own uniform buffer, take
 * turns: orphan the buffer with glBufferData(NULL), update it with
 * glBufferSubData, then draw a colour read from it. Nothing waits for the
 * GPU in between, so the buffer is usually still busy when it is updated.
 * GTK 4's ngl renderer works the same way: one context per window and
 * popover, and a small uniform buffer orphaned and updated every frame.
 *
 * After each batch, each context reads back its framebuffer, which must
 * show the colour it last wrote to its own buffer.
 *
 * Build (Ubuntu: apt install libegl-dev libgles-dev):
 *   cc -O2 ubo-two-contexts.c -o ubo-two-contexts -ldl
 * Run:
 *   ./ubo-two-contexts [batches] [iterations] [draws] [contexts] [orphan]
 * Defaults: 20 batches of 20 iterations, 8 draws, 2 contexts, orphan 1.
 * The exit status is 0 when every readback is right.
 */
#define EGL_NO_PROTOTYPES
#define GL_GLES_PROTOTYPES 0
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES3/gl31.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define SIZE 1024

static PFNEGLGETPROCADDRESSPROC egl_proc;

#define GL_FUNCS(X) \
   X(PFNGLGENBUFFERSPROC, glGenBuffers) \
   X(PFNGLBINDBUFFERPROC, glBindBuffer) \
   X(PFNGLBUFFERDATAPROC, glBufferData) \
   X(PFNGLBUFFERSUBDATAPROC, glBufferSubData) \
   X(PFNGLBINDBUFFERBASEPROC, glBindBufferBase) \
   X(PFNGLGENTEXTURESPROC, glGenTextures) \
   X(PFNGLBINDTEXTUREPROC, glBindTexture) \
   X(PFNGLTEXSTORAGE2DPROC, glTexStorage2D) \
   X(PFNGLGENFRAMEBUFFERSPROC, glGenFramebuffers) \
   X(PFNGLBINDFRAMEBUFFERPROC, glBindFramebuffer) \
   X(PFNGLFRAMEBUFFERTEXTURE2DPROC, glFramebufferTexture2D) \
   X(PFNGLCHECKFRAMEBUFFERSTATUSPROC, glCheckFramebufferStatus) \
   X(PFNGLCREATESHADERPROC, glCreateShader) \
   X(PFNGLSHADERSOURCEPROC, glShaderSource) \
   X(PFNGLCOMPILESHADERPROC, glCompileShader) \
   X(PFNGLGETSHADERIVPROC, glGetShaderiv) \
   X(PFNGLGETSHADERINFOLOGPROC, glGetShaderInfoLog) \
   X(PFNGLCREATEPROGRAMPROC, glCreateProgram) \
   X(PFNGLATTACHSHADERPROC, glAttachShader) \
   X(PFNGLLINKPROGRAMPROC, glLinkProgram) \
   X(PFNGLGETPROGRAMIVPROC, glGetProgramiv) \
   X(PFNGLUSEPROGRAMPROC, glUseProgram) \
   X(PFNGLGENVERTEXARRAYSPROC, glGenVertexArrays) \
   X(PFNGLBINDVERTEXARRAYPROC, glBindVertexArray) \
   X(PFNGLVIEWPORTPROC, glViewport) \
   X(PFNGLDRAWARRAYSPROC, glDrawArrays) \
   X(PFNGLREADPIXELSPROC, glReadPixels) \
   X(PFNGLGETSTRINGPROC, glGetString) \
   X(PFNGLGETERRORPROC, glGetError)

#define DECLARE(type, name) static type p_##name;
GL_FUNCS(DECLARE)

static const char *vs_src =
   "#version 310 es\n"
   "void main() {\n"
   "   vec2 p = vec2(gl_VertexID == 1 ? 3.0 : -1.0, gl_VertexID == 2 ? 3.0 : -1.0);\n"
   "   gl_Position = vec4(p, 0.0, 1.0);\n"
   "}\n";

static const char *fs_src =
   "#version 310 es\n"
   "precision highp float;\n"
   "layout(std140, binding = 0) uniform Globals { vec4 color; };\n"
   "out vec4 o;\n"
   "void main() { o = color; }\n";

static GLuint
shader(GLenum type, const char *src)
{
   GLuint s = p_glCreateShader(type);
   GLint ok;

   p_glShaderSource(s, 1, &src, NULL);
   p_glCompileShader(s);
   p_glGetShaderiv(s, GL_COMPILE_STATUS, &ok);
   if (!ok) {
      char log[1024];
      p_glGetShaderInfoLog(s, sizeof(log), NULL, log);
      fprintf(stderr, "shader: %s\n", log);
      exit(1);
   }
   return s;
}

struct ctx {
   EGLContext egl;
   GLuint ubo;
   unsigned char last[4];
};

static void
setup(struct ctx *c)
{
   GLuint tex, fb, prog, vao;
   GLint ok;

   p_glGenTextures(1, &tex);
   p_glBindTexture(GL_TEXTURE_2D, tex);
   p_glTexStorage2D(GL_TEXTURE_2D, 1, GL_RGBA8, SIZE, SIZE);
   p_glGenFramebuffers(1, &fb);
   p_glBindFramebuffer(GL_FRAMEBUFFER, fb);
   p_glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, tex, 0);
   if (p_glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
      fprintf(stderr, "framebuffer incomplete\n");
      exit(1);
   }

   prog = p_glCreateProgram();
   p_glAttachShader(prog, shader(GL_VERTEX_SHADER, vs_src));
   p_glAttachShader(prog, shader(GL_FRAGMENT_SHADER, fs_src));
   p_glLinkProgram(prog);
   p_glGetProgramiv(prog, GL_LINK_STATUS, &ok);
   if (!ok) {
      fprintf(stderr, "link failed\n");
      exit(1);
   }
   p_glUseProgram(prog);
   p_glGenVertexArrays(1, &vao);
   p_glBindVertexArray(vao);
   p_glViewport(0, 0, SIZE, SIZE);

   /* Like GTK's globals buffer: small, GL_STREAM_DRAW, bound to binding 0. */
   p_glGenBuffers(1, &c->ubo);
   p_glBindBuffer(GL_UNIFORM_BUFFER, c->ubo);
   p_glBufferData(GL_UNIFORM_BUFFER, 128, NULL, GL_STREAM_DRAW);
   p_glBindBufferBase(GL_UNIFORM_BUFFER, 0, c->ubo);
}

int
main(int argc, char **argv)
{
   int batches = argc > 1 ? atoi(argv[1]) : 20;
   int iters = argc > 2 ? atoi(argv[2]) : 20;
   int draws = argc > 3 ? atoi(argv[3]) : 8;
   int nctx = argc > 4 ? atoi(argv[4]) : 2;
   int orphan = argc > 5 ? atoi(argv[5]) : 1;
   void *lib = dlopen("libEGL.so.1", RTLD_NOW);
   struct ctx c[2];
   int bad = 0;

   if (!lib) {
      fprintf(stderr, "%s\n", dlerror());
      return 1;
   }
   egl_proc = (PFNEGLGETPROCADDRESSPROC)dlsym(lib, "eglGetProcAddress");
   PFNEGLGETPLATFORMDISPLAYPROC get_display =
      (PFNEGLGETPLATFORMDISPLAYPROC)egl_proc("eglGetPlatformDisplay");
   PFNEGLINITIALIZEPROC initialize = (PFNEGLINITIALIZEPROC)egl_proc("eglInitialize");
   PFNEGLBINDAPIPROC bind_api = (PFNEGLBINDAPIPROC)egl_proc("eglBindAPI");
   PFNEGLCREATECONTEXTPROC create_context =
      (PFNEGLCREATECONTEXTPROC)egl_proc("eglCreateContext");
   PFNEGLMAKECURRENTPROC make_current = (PFNEGLMAKECURRENTPROC)egl_proc("eglMakeCurrent");

#define LOAD(type, name) p_##name = (type)egl_proc(#name);
   GL_FUNCS(LOAD)

   EGLDisplay dpy = get_display(EGL_PLATFORM_SURFACELESS_MESA, EGL_DEFAULT_DISPLAY, NULL);
   if (dpy == EGL_NO_DISPLAY || !initialize(dpy, NULL, NULL)) {
      fprintf(stderr, "no surfaceless EGL display\n");
      return 1;
   }
   bind_api(EGL_OPENGL_ES_API);
   static const EGLint attribs[] = {
      EGL_CONTEXT_MAJOR_VERSION, 3, EGL_CONTEXT_MINOR_VERSION, 1, EGL_NONE
   };
   for (int k = 0; k < 2; k++) {
      c[k].egl = create_context(dpy, EGL_NO_CONFIG_KHR, EGL_NO_CONTEXT, attribs);
      if (c[k].egl == EGL_NO_CONTEXT ||
          !make_current(dpy, EGL_NO_SURFACE, EGL_NO_SURFACE, c[k].egl)) {
         fprintf(stderr, "context %d failed\n", k);
         return 1;
      }
      setup(&c[k]);
   }
   printf("%s, %s\n", p_glGetString(GL_RENDERER), p_glGetString(GL_VERSION));

   for (int b = 0; b < batches; b++) {
      for (int i = 0; i < iters; i++) {
         for (int k = 0; k < 2; k++) {
            unsigned char v = 1 + (b * iters + i) % 250;
            float color[4] = { v / 255.0f, k ? 1.0f : 0.0f, k ? 0.0f : 1.0f, 1.0f };

            if (k >= nctx)
               continue;
            make_current(dpy, EGL_NO_SURFACE, EGL_NO_SURFACE, c[k].egl);
            /* GTK orphans its globals buffer at the start of every frame. */
            if (orphan)
               p_glBufferData(GL_UNIFORM_BUFFER, 128, NULL, GL_STREAM_DRAW);
            p_glBufferSubData(GL_UNIFORM_BUFFER, 0, sizeof(color), color);
            for (int d = 0; d < draws; d++)
               p_glDrawArrays(GL_TRIANGLES, 0, 3);
            c[k].last[0] = v;
            c[k].last[1] = k ? 255 : 0;
            c[k].last[2] = k ? 0 : 255;
         }
      }
      for (int k = 0; k < nctx; k++) {
         unsigned char px[4];

         make_current(dpy, EGL_NO_SURFACE, EGL_NO_SURFACE, c[k].egl);
         p_glReadPixels(SIZE / 2, SIZE / 2, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, px);
         if (abs(px[0] - c[k].last[0]) > 1 || px[1] != c[k].last[1] || px[2] != c[k].last[2]) {
            if (bad < 10)
               printf("batch %d, context %d: got %3d %3d %3d, expected %3d %3d %3d\n",
                      b, k, px[0], px[1], px[2], c[k].last[0], c[k].last[1], c[k].last[2]);
            bad++;
         }
      }
   }
   printf("%d contexts, orphan %d: %d of %d readbacks wrong, GL error 0x%x\n",
          nctx, orphan, bad, batches * nctx, p_glGetError());
   return bad != 0;
}
