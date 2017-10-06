// nuklear_gles2.h

#ifndef __INC_NK_GLES2_H__
#define __INC_NK_GLES2_H__

#include "android/input.h"

#define NK_INCLUDE_FIXED_TYPES
#define NK_INCLUDE_STANDARD_IO
#define NK_INCLUDE_STANDARD_VARARGS
#define NK_INCLUDE_DEFAULT_ALLOCATOR
#define NK_INCLUDE_VERTEX_BUFFER_OUTPUT
#define NK_INCLUDE_FONT_BAKING
#define NK_INCLUDE_DEFAULT_FONT
#include "nuklear.h"

#ifdef __cplusplus
extern "C" {
#endif

struct nk_glesv2_iface {
	void (*get_window_size)(void* ud, int* w, int* h);
	void (*get_drawable_size)(void* ud, int* w, int* h);
};

NK_API struct nk_context*   nk_glesv2_init(const struct nk_glesv2_iface* iface, void* ud);
NK_API void                 nk_glesv2_font_stash_begin(struct nk_font_atlas **atlas);
NK_API void                 nk_glesv2_font_stash_end(void);
NK_API int                  nk_glesv2_handle_event(const AInputEvent *evt);
NK_API void                 nk_glesv2_render(enum nk_anti_aliasing , int max_vertex_buffer, int max_element_buffer);
NK_API void                 nk_glesv2_shutdown(void);
NK_API void                 nk_glesv2_device_destroy(void);
NK_API void                 nk_glesv2_device_create(void);

#ifdef __cplusplus
}
#endif

#endif//__INC_NK_GLES2_H__

