/* Export one NV12 VA surface as dmabufs and print, for each object, the
 * size the driver reports and the size of the fd. Before "nouveau: report
 * the size of exported buffers" nouveau reports 0.
 *
 *   cc -o va-export-size va-export-size.c -lva -lva-drm
 *   LIBVA_DRIVERS_PATH=<dir> ./va-export-size [width height]
 */
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <va/va.h>
#include <va/va_drm.h>
#include <va/va_drmcommon.h>

int main(int argc, char **argv)
{
   int w = argc > 2 ? atoi(argv[1]) : 1920;
   int h = argc > 2 ? atoi(argv[2]) : 1080;
   int fd = open("/dev/dri/renderD128", O_RDWR);
   VADisplay dpy;
   VASurfaceID surf;
   VASurfaceAttrib attr = {
      .type = VASurfaceAttribPixelFormat,
      .flags = VA_SURFACE_ATTRIB_SETTABLE,
      .value.type = VAGenericValueTypeInteger,
      .value.value.i = VA_FOURCC_NV12,
   };
   VADRMPRIMESurfaceDescriptor desc;
   VAStatus st;
   int major, minor, bad = 0;

   if (fd < 0) {
      perror("open renderD128");
      return 1;
   }
   dpy = vaGetDisplayDRM(fd);
   if (vaInitialize(dpy, &major, &minor) != VA_STATUS_SUCCESS) {
      fprintf(stderr, "vaInitialize failed\n");
      return 1;
   }
   printf("driver: %s\n", vaQueryVendorString(dpy));
   st = vaCreateSurfaces(dpy, VA_RT_FORMAT_YUV420, w, h, &surf, 1, &attr, 1);
   if (st != VA_STATUS_SUCCESS) {
      fprintf(stderr, "vaCreateSurfaces: %s\n", vaErrorStr(st));
      return 1;
   }
   st = vaExportSurfaceHandle(dpy, surf, VA_SURFACE_ATTRIB_MEM_TYPE_DRM_PRIME_2,
                              VA_EXPORT_SURFACE_READ_ONLY |
                              VA_EXPORT_SURFACE_SEPARATE_LAYERS, &desc);
   if (st != VA_STATUS_SUCCESS) {
      fprintf(stderr, "vaExportSurfaceHandle: %s\n", vaErrorStr(st));
      return 1;
   }
   for (unsigned i = 0; i < desc.num_objects; i++) {
      off_t real = lseek(desc.objects[i].fd, 0, SEEK_END);

      printf("%dx%d object %u: reported %u, fd %lld, modifier 0x%llx%s\n",
             w, h, i, desc.objects[i].size, (long long)real,
             (unsigned long long)desc.objects[i].drm_format_modifier,
             desc.objects[i].size == real ? "" : "  <-- differs");
      if (desc.objects[i].size != real)
         bad = 1;
      close(desc.objects[i].fd);
   }
   vaDestroySurfaces(dpy, &surf, 1);
   vaTerminate(dpy);
   close(fd);
   return bad ? 2 : 0;
}
