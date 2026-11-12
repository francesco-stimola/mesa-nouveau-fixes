/*
 * Reproducer for patch 0001 (glClearTexImage), by Kush Chandak
 * (https://github.com/francesco-stimola/mesa-nouveau-fixes/issues/1).
 *
 * Clears a depth texture and a color texture with glClearTexImage. Since
 * Mesa 25.2, util_clear_texture_as_surface() hands the driver a
 * pipe_surface template on the stack, and the nv50 and nvc0 clear hooks
 * read it as a larger nv50_surface. nv30 has the same bug (0012), but this
 * reproducer was never run on such a GPU.
 *
 * Build: gcc -O0 -o cleartex cleartex.c -ldl
 * Run:   ./cleartex          clear one depth and one color texture, read them
 *                            back and count wrong texels (exit 1 if any)
 *        ./cleartex depth|color|both
 *                            many clears at various sizes and levels; on stock
 *                            Mesa this can make the kernel log a GR fault
 *
 * Needs a GL 3.3 core context with GL_ARB_clear_texture, so nv50 can run it too.
 */
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>

typedef void *EGLDisplay, *EGLContext, *EGLConfig, *EGLSurface;
typedef int EGLint;
typedef unsigned int EGLenum, EGLBoolean, GLenum, GLuint, GLbitfield;
typedef int GLint, GLsizei;

#define EGL_PLATFORM_SURFACELESS_MESA 0x31DD
#define EGL_NONE 0x3038
#define EGL_OPENGL_API 0x30A2
#define EGL_CONTEXT_MAJOR_VERSION 0x3098
#define EGL_CONTEXT_MINOR_VERSION 0x30FB
#define EGL_CONTEXT_OPENGL_PROFILE_MASK 0x30FD
#define EGL_CONTEXT_OPENGL_CORE_PROFILE_BIT 0x1

#define GL_TEXTURE_2D 0x0DE1
#define GL_DEPTH_COMPONENT 0x1902
#define GL_DEPTH_COMPONENT24 0x81A6
#define GL_RGBA 0x1908
#define GL_RGBA8 0x8058
#define GL_FLOAT 0x1406
#define GL_UNSIGNED_BYTE 0x1401
#define GL_RENDERER 0x1F01
#define GL_VERSION 0x1F02
#define GL_EXTENSIONS 0x1F03
#define GL_NUM_EXTENSIONS 0x821D

static void *(*eglGetProcAddress_)(const char *);
#define LOAD(var, name) do { *(void **)&var = eglGetProcAddress_(name); \
	if (!var) { fprintf(stderr, "missing %s\n", name); return 1; } } while (0)

int main(int argc, char **argv)
{
	const char *what = argc > 1 ? argv[1] : "verify";
	void *egl = dlopen("libEGL.so.1", RTLD_NOW);
	if (!egl) { fprintf(stderr, "dlopen libEGL: %s\n", dlerror()); return 1; }
	eglGetProcAddress_ = dlsym(egl, "eglGetProcAddress");

	EGLDisplay (*GetPlatformDisplay)(EGLenum, void *, const void *);
	EGLBoolean (*Initialize)(EGLDisplay, EGLint *, EGLint *);
	EGLBoolean (*BindAPI)(EGLenum);
	EGLContext (*CreateContext)(EGLDisplay, EGLConfig, EGLContext, const EGLint *);
	EGLBoolean (*MakeCurrent)(EGLDisplay, EGLSurface, EGLSurface, EGLContext);
	LOAD(GetPlatformDisplay, "eglGetPlatformDisplay");
	LOAD(Initialize, "eglInitialize");
	LOAD(BindAPI, "eglBindAPI");
	LOAD(CreateContext, "eglCreateContext");
	LOAD(MakeCurrent, "eglMakeCurrent");

	EGLDisplay dpy = GetPlatformDisplay(EGL_PLATFORM_SURFACELESS_MESA, NULL, NULL);
	EGLint maj, min;
	if (!dpy || !Initialize(dpy, &maj, &min)) { fprintf(stderr, "eglInitialize failed\n"); return 1; }
	BindAPI(EGL_OPENGL_API);
	const EGLint attrs[] = { EGL_CONTEXT_MAJOR_VERSION, 3, EGL_CONTEXT_MINOR_VERSION, 3,
		EGL_CONTEXT_OPENGL_PROFILE_MASK, EGL_CONTEXT_OPENGL_CORE_PROFILE_BIT, EGL_NONE };
	EGLContext ctx = CreateContext(dpy, NULL, NULL, attrs);
	if (!ctx || !MakeCurrent(dpy, NULL, NULL, ctx)) { fprintf(stderr, "context failed\n"); return 1; }

	const unsigned char *(*GetString)(GLenum);
	void (*GenTextures)(GLsizei, GLuint *);
	void (*BindTexture)(GLenum, GLuint);
	void (*TexStorage2D)(GLenum, GLsizei, GLenum, GLsizei, GLsizei);
	void (*ClearTexImage)(GLuint, GLint, GLenum, GLenum, const void *);
	void (*Finish)(void);
	void (*GetTexImage)(GLenum, GLint, GLenum, GLenum, void *);
	GLenum (*GetError)(void);
	const unsigned char *(*GetStringi)(GLenum, GLuint);
	void (*GetIntegerv)(GLenum, GLint *);
	LOAD(GetString, "glGetString");
	LOAD(GetStringi, "glGetStringi");
	LOAD(GetIntegerv, "glGetIntegerv");
	LOAD(GenTextures, "glGenTextures");
	LOAD(BindTexture, "glBindTexture");
	LOAD(TexStorage2D, "glTexStorage2D");
	LOAD(ClearTexImage, "glClearTexImage");
	LOAD(Finish, "glFinish");
	LOAD(GetError, "glGetError");
	LOAD(GetTexImage, "glGetTexImage");
	printf("GL: %s | %s\n", GetString(GL_RENDERER), GetString(GL_VERSION));

	GLint num_ext = 0, has_clear = 0;
	GetIntegerv(GL_NUM_EXTENSIONS, &num_ext);
	for (GLint i = 0; i < num_ext; i++)
		has_clear |= !strcmp((const char *)GetStringi(GL_EXTENSIONS, i), "GL_ARB_clear_texture");
	if (!has_clear) { fprintf(stderr, "GL_ARB_clear_texture not supported\n"); return 1; }

	if (!strcmp(what, "verify")) {
		static float z[64 * 64];
		static unsigned char c[64 * 64 * 4];
		float half = 0.5f;
		unsigned char red[4] = { 255, 0, 0, 255 };
		GLuint t[2];
		int bad = 0, total = 0;
		GenTextures(2, t);
		BindTexture(GL_TEXTURE_2D, t[0]);
		TexStorage2D(GL_TEXTURE_2D, 1, GL_DEPTH_COMPONENT24, 64, 64);
		ClearTexImage(t[0], 0, GL_DEPTH_COMPONENT, GL_FLOAT, &half);
		GetTexImage(GL_TEXTURE_2D, 0, GL_DEPTH_COMPONENT, GL_FLOAT, z);
		for (int i = 0; i < 64 * 64; i++)
			bad += z[i] < 0.49f || z[i] > 0.51f;
		printf("depth cleared to 0.5: %d of 4096 texels wrong (first = %f)\n", bad, z[0]);
		total += bad;
		bad = 0;
		BindTexture(GL_TEXTURE_2D, t[1]);
		TexStorage2D(GL_TEXTURE_2D, 1, GL_RGBA8, 64, 64);
		ClearTexImage(t[1], 0, GL_RGBA, GL_UNSIGNED_BYTE, red);
		GetTexImage(GL_TEXTURE_2D, 0, GL_RGBA, GL_UNSIGNED_BYTE, c);
		for (int i = 0; i < 64 * 64; i++)
			bad += memcmp(&c[i * 4], red, 4) != 0;
		printf("color cleared to red: %d of 4096 texels wrong (first = %u,%u,%u,%u)\n", bad, c[0], c[1], c[2], c[3]);
		total += bad;
		printf("glGetError=0x%x\n", GetError());
		return total != 0;
	}
	for (int i = 0; i < 20; i++) {
		GLuint t[2];
		GenTextures(2, t);
		int size = 64 << (i % 5);
		if (!strcmp(what, "depth") || !strcmp(what, "both")) {
			float one = 1.0f;
			BindTexture(GL_TEXTURE_2D, t[0]);
			TexStorage2D(GL_TEXTURE_2D, 3, GL_DEPTH_COMPONENT24, size, size);
			for (int l = 0; l < 3; l++)
				ClearTexImage(t[0], l, GL_DEPTH_COMPONENT, GL_FLOAT, &one);
		}
		if (!strcmp(what, "color") || !strcmp(what, "both")) {
			unsigned char px[4] = { 255, 0, 0, 255 };
			BindTexture(GL_TEXTURE_2D, t[1]);
			TexStorage2D(GL_TEXTURE_2D, 3, GL_RGBA8, size, size);
			for (int l = 0; l < 3; l++)
				ClearTexImage(t[1], l, GL_RGBA, GL_UNSIGNED_BYTE, px);
		}
		Finish();
	}
	printf("done, glGetError=0x%x\n", GetError());
	return 0;
}
