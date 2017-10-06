// nuklear_gles2.c

#include <string.h>
#include <android/log.h>
#include <gl3stub.h>

#define NK_IMPLEMENTATION
#include "nuklear_gles2.h"

#define LOGW(...) ((void)__android_log_print(ANDROID_LOG_WARN, "nuklear", __VA_ARGS__))

struct nk_glesv2_device {
    struct nk_buffer cmds;
    struct nk_draw_null_texture null;
    GLuint vbo, ebo;
    GLuint prog;
    GLuint vert_shdr;
    GLuint frag_shdr;
    GLint attrib_pos;
    GLint attrib_uv;
    GLint attrib_col;
    GLint uniform_tex;
    GLint uniform_proj;
    GLuint font_tex;
    GLsizei vs;
    size_t vp, vt, vc;
};

struct nk_glesv2_vertex {
    GLfloat position[2];
    GLfloat uv[2];
    nk_byte col[4];
};

static struct nk_glesv2 {
	const struct nk_glesv2_iface* iface;
	void* iface_ud;
    struct nk_glesv2_device ogl;
    struct nk_context ctx;
    struct nk_font_atlas atlas;
} nk;


#define NK_SHADER_VERSION "#version 100\n"


static void show_shader_error(int shader, const char* fname) {
	GLint infoLen = 0;
	glGetShaderiv ( shader, GL_INFO_LOG_LENGTH, &infoLen );
	if ( infoLen > 0 ) {
		char _cache[4096];
		char* infoLog = infoLen < (sizeof(_cache) - 1) ? _cache : (char*)malloc (sizeof(char) * (infoLen + 1) );
		glGetShaderInfoLog ( shader, infoLen, NULL, infoLog );
		infoLog[infoLen] = '\0';
		LOGW("Error linking program(%s):\r\n%s\r\n", fname, infoLog);
		if( infoLog!=_cache )
			free ( infoLog );
	}

	glDeleteShader ( shader );
}

NK_API void
nk_glesv2_device_create(void)
{
    GLint status;
    static const GLchar *vertex_shader =
        NK_SHADER_VERSION
        "uniform mat4 ProjMtx;\n"
        "attribute vec2 Position;\n"
        "attribute vec2 TexCoord;\n"
        "attribute vec4 Color;\n"
        "varying vec2 Frag_UV;\n"
        "varying vec4 Frag_Color;\n"
        "void main() {\n"
        "   Frag_UV = TexCoord;\n"
        "   Frag_Color = Color;\n"
        "   gl_Position = ProjMtx * vec4(Position.xy, 0, 1);\n"
        "}\n";
    static const GLchar *fragment_shader =
        NK_SHADER_VERSION
        "precision mediump float;\n"
        "uniform sampler2D Texture;\n"
        "varying vec2 Frag_UV;\n"
        "varying vec4 Frag_Color;\n"
        "void main(){\n"
        "   gl_FragColor = Frag_Color * texture2D(Texture, Frag_UV);\n"
        "}\n";

    struct nk_glesv2_device *dev = &nk.ogl;
    
    nk_buffer_init_default(&dev->cmds);
    dev->prog = glCreateProgram();
    dev->vert_shdr = glCreateShader(GL_VERTEX_SHADER);
    dev->frag_shdr = glCreateShader(GL_FRAGMENT_SHADER);
    glShaderSource(dev->vert_shdr, 1, &vertex_shader, 0);
    glShaderSource(dev->frag_shdr, 1, &fragment_shader, 0);
    glCompileShader(dev->vert_shdr);
    glCompileShader(dev->frag_shdr);
    glGetShaderiv(dev->vert_shdr, GL_COMPILE_STATUS, &status);
    assert (status == GL_TRUE);
    glGetShaderiv(dev->frag_shdr, GL_COMPILE_STATUS, &status);
    assert (status == GL_TRUE);
    glAttachShader(dev->prog, dev->vert_shdr);
    glAttachShader(dev->prog, dev->frag_shdr);
    glLinkProgram(dev->prog);
    glGetProgramiv(dev->prog, GL_LINK_STATUS, &status);
    assert (status == GL_TRUE);

    dev->uniform_tex = glGetUniformLocation(dev->prog, "Texture");
    dev->uniform_proj = glGetUniformLocation(dev->prog, "ProjMtx");
    dev->attrib_pos = glGetAttribLocation(dev->prog, "Position");
    dev->attrib_uv = glGetAttribLocation(dev->prog, "TexCoord");
    dev->attrib_col = glGetAttribLocation(dev->prog, "Color");
    {
        dev->vs = sizeof(struct nk_glesv2_vertex);
        dev->vp = offsetof(struct nk_glesv2_vertex, position);
        dev->vt = offsetof(struct nk_glesv2_vertex, uv);
        dev->vc = offsetof(struct nk_glesv2_vertex, col);
        
        /* Allocate buffers */
        glGenBuffers(1, &dev->vbo);
        glGenBuffers(1, &dev->ebo);
    }
    glBindTexture(GL_TEXTURE_2D, 0);
    glBindBuffer(GL_ARRAY_BUFFER, 0);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, 0);
}

NK_INTERN void
nk_glesv2_device_upload_atlas(const void *image, int width, int height)
{
    struct nk_glesv2_device *dev = &nk.ogl;
    glGenTextures(1, &dev->font_tex);
    glBindTexture(GL_TEXTURE_2D, dev->font_tex);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, (GLsizei)width, (GLsizei)height, 0,
                GL_RGBA, GL_UNSIGNED_BYTE, image);
}

NK_API void
nk_glesv2_device_destroy(void)
{
    struct nk_glesv2_device *dev = &nk.ogl;
    glDetachShader(dev->prog, dev->vert_shdr);
    glDetachShader(dev->prog, dev->frag_shdr);
    glDeleteShader(dev->vert_shdr);
    glDeleteShader(dev->frag_shdr);
    glDeleteProgram(dev->prog);
    glDeleteTextures(1, &dev->font_tex);
    glDeleteBuffers(1, &dev->vbo);
    glDeleteBuffers(1, &dev->ebo);
    nk_buffer_free(&dev->cmds);
}

NK_API void
nk_glesv2_render(enum nk_anti_aliasing AA, int max_vertex_buffer, int max_element_buffer)
{
    struct nk_glesv2_device *dev = &nk.ogl;
    int width, height;
    int display_width, display_height;
    struct nk_vec2 scale;
    GLfloat ortho[4][4] = {
        {2.0f, 0.0f, 0.0f, 0.0f},
        {0.0f,-2.0f, 0.0f, 0.0f},
        {0.0f, 0.0f,-1.0f, 0.0f},
        {-1.0f,1.0f, 0.0f, 1.0f},
    };
    nk.iface->get_window_size(nk.iface_ud, &width, &height);
    nk.iface->get_drawable_size(nk.iface_ud, &display_width, &display_height);
    ortho[0][0] /= (GLfloat)width;
    ortho[1][1] /= (GLfloat)height;

    scale.x = (float)display_width/(float)width;
    scale.y = (float)display_height/(float)height;

    /* setup global state */
    glViewport(0,0,display_width,display_height);
    glEnable(GL_BLEND);
    glBlendEquation(GL_FUNC_ADD);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    glDisable(GL_CULL_FACE);
    glDisable(GL_DEPTH_TEST);
    glEnable(GL_SCISSOR_TEST);
    glActiveTexture(GL_TEXTURE0);

    /* setup program */
    glUseProgram(dev->prog);
    glUniform1i(dev->uniform_tex, 0);
    glUniformMatrix4fv(dev->uniform_proj, 1, GL_FALSE, &ortho[0][0]);
    {
        /* convert from command queue into draw list and draw to screen */
        const struct nk_draw_command *cmd;
        void *vertices, *elements;
        const nk_draw_index *offset = NULL;

        /* Bind buffers */
        glBindBuffer(GL_ARRAY_BUFFER, dev->vbo);
        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, dev->ebo);
        
        {
            /* buffer setup */
            glEnableVertexAttribArray((GLuint)dev->attrib_pos);
            glEnableVertexAttribArray((GLuint)dev->attrib_uv);
            glEnableVertexAttribArray((GLuint)dev->attrib_col);

            glVertexAttribPointer((GLuint)dev->attrib_pos, 2, GL_FLOAT, GL_FALSE, dev->vs, (void*)dev->vp);
            glVertexAttribPointer((GLuint)dev->attrib_uv, 2, GL_FLOAT, GL_FALSE, dev->vs, (void*)dev->vt);
            glVertexAttribPointer((GLuint)dev->attrib_col, 4, GL_UNSIGNED_BYTE, GL_TRUE, dev->vs, (void*)dev->vc);
        }

        glBufferData(GL_ARRAY_BUFFER, max_vertex_buffer, NULL, GL_STREAM_DRAW);
        glBufferData(GL_ELEMENT_ARRAY_BUFFER, max_element_buffer, NULL, GL_STREAM_DRAW);

        /* load vertices/elements directly into vertex/element buffer */
        vertices = malloc((size_t)max_vertex_buffer);
        elements = malloc((size_t)max_element_buffer);
        {
            /* fill convert configuration */
            struct nk_convert_config config;
            static const struct nk_draw_vertex_layout_element vertex_layout[] = {
                {NK_VERTEX_POSITION, NK_FORMAT_FLOAT, NK_OFFSETOF(struct nk_glesv2_vertex, position)},
                {NK_VERTEX_TEXCOORD, NK_FORMAT_FLOAT, NK_OFFSETOF(struct nk_glesv2_vertex, uv)},
                {NK_VERTEX_COLOR, NK_FORMAT_R8G8B8A8, NK_OFFSETOF(struct nk_glesv2_vertex, col)},
                {NK_VERTEX_LAYOUT_END}
            };
            NK_MEMSET(&config, 0, sizeof(config));
            config.vertex_layout = vertex_layout;
            config.vertex_size = sizeof(struct nk_glesv2_vertex);
            config.vertex_alignment = NK_ALIGNOF(struct nk_glesv2_vertex);
            config.null = dev->null;
            config.circle_segment_count = 22;
            config.curve_segment_count = 22;
            config.arc_segment_count = 22;
            config.global_alpha = 1.0f;
            config.shape_AA = AA;
            config.line_AA = AA;

            /* setup buffers to load vertices and elements */
            {struct nk_buffer vbuf, ebuf;
            nk_buffer_init_fixed(&vbuf, vertices, (nk_size)max_vertex_buffer);
            nk_buffer_init_fixed(&ebuf, elements, (nk_size)max_element_buffer);
            nk_convert(&nk.ctx, &dev->cmds, &vbuf, &ebuf, &config);}
        }
        glBufferSubData(GL_ARRAY_BUFFER, 0, (size_t)max_vertex_buffer, vertices);
        glBufferSubData(GL_ELEMENT_ARRAY_BUFFER, 0, (size_t)max_element_buffer, elements);
        free(vertices);
        free(elements);

        /* iterate over and execute each draw command */
        nk_draw_foreach(cmd, &nk.ctx, &dev->cmds) {
            if (!cmd->elem_count) continue;
            glBindTexture(GL_TEXTURE_2D, (GLuint)cmd->texture.id);
            glScissor((GLint)(cmd->clip_rect.x * scale.x),
                (GLint)((height - (GLint)(cmd->clip_rect.y + cmd->clip_rect.h)) * scale.y),
                (GLint)(cmd->clip_rect.w * scale.x),
                (GLint)(cmd->clip_rect.h * scale.y));
            glDrawElements(GL_TRIANGLES, (GLsizei)cmd->elem_count, GL_UNSIGNED_SHORT, offset);
            offset += cmd->elem_count;
        }
        nk_clear(&nk.ctx);
    }

    glUseProgram(0);
    glBindBuffer(GL_ARRAY_BUFFER, 0);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, 0);

    glDisable(GL_BLEND);
    glDisable(GL_SCISSOR_TEST);
}

static void
nk_glesv2_clipbard_paste(nk_handle usr, struct nk_text_edit *edit)
{
    const char *text = "TODO: clipbard paste"; // SDL_GetClipboardText();
    if (text) nk_textedit_paste(edit, text, nk_strlen(text));
    (void)usr;
}

static void
nk_glesv2_clipbard_copy(nk_handle usr, const char *text, int len)
{
    char *str = 0;
    (void)usr;
    if (!len) return;
    str = (char*)malloc((size_t)len+1);
    if (!str) return;
    memcpy(str, text, (size_t)len);
    str[len] = '\0';
    // TODO : SDL_SetClipboardText(str);
    free(str);
}

NK_API struct nk_context*
nk_glesv2_init(const struct nk_glesv2_iface* iface, void* ud)
{
    nk_init_default(&nk.ctx, 0);
    nk.iface = iface;
    nk.iface_ud = ud;
    nk.ctx.clip.copy = nk_glesv2_clipbard_copy;
    nk.ctx.clip.paste = nk_glesv2_clipbard_paste;
    nk.ctx.clip.userdata = nk_handle_ptr(0);
    nk_glesv2_device_create();
    return &nk.ctx;
}

NK_API void
nk_glesv2_font_stash_begin(struct nk_font_atlas **atlas)
{
    nk_font_atlas_init_default(&nk.atlas);
    nk_font_atlas_begin(&nk.atlas);
    *atlas = &nk.atlas;
}

NK_API void
nk_glesv2_font_stash_end(void)
{
    const void *image; int w, h;
    image = nk_font_atlas_bake(&nk.atlas, &w, &h, NK_FONT_ATLAS_RGBA32);
    nk_glesv2_device_upload_atlas(image, w, h);
    nk_font_atlas_end(&nk.atlas, nk_handle_id((int)nk.ogl.font_tex), &nk.ogl.null);
    if (nk.atlas.default_font)
        nk_style_set_font(&nk.ctx, &nk.atlas.default_font->handle);

}

NK_API int
nk_glesv2_handle_event(const AInputEvent *evt)
{
    struct nk_context *ctx = &nk.ctx;
    int evt_type = AInputEvent_getType(evt);

    if (evt_type==AINPUT_EVENT_TYPE_MOTION) {
        int action = AMotionEvent_getAction(evt);
		int x = AMotionEvent_getX(evt, 0);
		int y = AMotionEvent_getY(evt, 0);

        if( action==AMOTION_EVENT_ACTION_DOWN || action==AMOTION_EVENT_ACTION_UP ) {
		    // mouse button
		    int down = action==AMOTION_EVENT_ACTION_DOWN;
		    nk_input_button(ctx, NK_BUTTON_LEFT, x, y, down);
		    /*
		    if (evt->button.button == SDL_BUTTON_LEFT) {
		        if (evt->button.clicks > 1)
		            nk_input_button(ctx, NK_BUTTON_DOUBLE, x, y, down);
		        nk_input_button(ctx, NK_BUTTON_LEFT, x, y, down);
		    } else if (evt->button.button == SDL_BUTTON_MIDDLE) {
		        nk_input_button(ctx, NK_BUTTON_MIDDLE, x, y, down);
		    } else if (evt->button.button == SDL_BUTTON_RIGHT) {
		        nk_input_button(ctx, NK_BUTTON_RIGHT, x, y, down);
		    }
		    */
		    return 1;
		} else if (action==AMOTION_EVENT_ACTION_MOVE) {
		    // mouse motion
		    /*
		    if (ctx->input.mouse.grabbed) {
		        nk_input_motion(ctx, x + evt->motion.xrel, y + evt->motion.yrel);
		    } else {
     		    nk_input_motion(ctx, x, y);
     		}
     		*/
     		nk_input_motion(ctx, x, y);
		    return 1;
		} else if (action==AMOTION_EVENT_ACTION_HOVER_MOVE) {
		    nk_input_motion(ctx, x, y);
		    return 1;
		}

    } else if( evt_type==AINPUT_EVENT_TYPE_KEY ) {
    	/*
    	// key events
        int down = evt->type == SDL_KEYDOWN;
        const Uint8* state = SDL_GetKeyboardState(0);
        SDL_Keycode sym = evt->key.keysym.sym;
        if (sym == SDLK_RSHIFT || sym == SDLK_LSHIFT)
            nk_input_key(ctx, NK_KEY_SHIFT, down);
        else if (sym == SDLK_DELETE)
            nk_input_key(ctx, NK_KEY_DEL, down);
        else if (sym == SDLK_RETURN)
            nk_input_key(ctx, NK_KEY_ENTER, down);
        else if (sym == SDLK_TAB)
            nk_input_key(ctx, NK_KEY_TAB, down);
        else if (sym == SDLK_BACKSPACE)
            nk_input_key(ctx, NK_KEY_BACKSPACE, down);
        else if (sym == SDLK_HOME) {
            nk_input_key(ctx, NK_KEY_TEXT_START, down);
            nk_input_key(ctx, NK_KEY_SCROLL_START, down);
        } else if (sym == SDLK_END) {
            nk_input_key(ctx, NK_KEY_TEXT_END, down);
            nk_input_key(ctx, NK_KEY_SCROLL_END, down);
        } else if (sym == SDLK_PAGEDOWN) {
            nk_input_key(ctx, NK_KEY_SCROLL_DOWN, down);
        } else if (sym == SDLK_PAGEUP) {
            nk_input_key(ctx, NK_KEY_SCROLL_UP, down);
        } else if (sym == SDLK_z)
            nk_input_key(ctx, NK_KEY_TEXT_UNDO, down && state[SDL_SCANCODE_LCTRL]);
        else if (sym == SDLK_r)
            nk_input_key(ctx, NK_KEY_TEXT_REDO, down && state[SDL_SCANCODE_LCTRL]);
        else if (sym == SDLK_c)
            nk_input_key(ctx, NK_KEY_COPY, down && state[SDL_SCANCODE_LCTRL]);
        else if (sym == SDLK_v)
            nk_input_key(ctx, NK_KEY_PASTE, down && state[SDL_SCANCODE_LCTRL]);
        else if (sym == SDLK_x)
            nk_input_key(ctx, NK_KEY_CUT, down && state[SDL_SCANCODE_LCTRL]);
        else if (sym == SDLK_b)
            nk_input_key(ctx, NK_KEY_TEXT_LINE_START, down && state[SDL_SCANCODE_LCTRL]);
        else if (sym == SDLK_e)
            nk_input_key(ctx, NK_KEY_TEXT_LINE_END, down && state[SDL_SCANCODE_LCTRL]);
        else if (sym == SDLK_UP)
            nk_input_key(ctx, NK_KEY_UP, down);
        else if (sym == SDLK_DOWN)
            nk_input_key(ctx, NK_KEY_DOWN, down);
        else if (sym == SDLK_LEFT) {
            if (state[SDL_SCANCODE_LCTRL])
                nk_input_key(ctx, NK_KEY_TEXT_WORD_LEFT, down);
            else nk_input_key(ctx, NK_KEY_LEFT, down);
        } else if (sym == SDLK_RIGHT) {
            if (state[SDL_SCANCODE_LCTRL])
                nk_input_key(ctx, NK_KEY_TEXT_WORD_RIGHT, down);
            else nk_input_key(ctx, NK_KEY_RIGHT, down);
        } else return 0;
        return 1;
		*/
    }
/*
   if (evt->type == SDL_KEYUP || evt->type == SDL_KEYDOWN) {
   } else if (evt->type == SDL_MOUSEBUTTONDOWN || evt->type == SDL_MOUSEBUTTONUP) {
   } else if (evt->type == SDL_MOUSEMOTION) {
   } else if (evt->type == SDL_TEXTINPUT) {
        // text input
        nk_glyph glyph;
        memcpy(glyph, evt->text.text, NK_UTF_SIZE);
        nk_input_glyph(ctx, glyph);
        return 1;
    } else if (evt->type == SDL_MOUSEWHEEL) {
        // mouse wheel
        nk_input_scroll(ctx,nk_vec2((float)evt->wheel.x,(float)evt->wheel.y));
        return 1;
    }
*/
    return 0;
}

NK_API
void nk_glesv2_shutdown(void)
{
    nk_font_atlas_clear(&nk.atlas);
    nk_free(&nk.ctx);
    nk_glesv2_device_destroy();
    memset(&nk, 0, sizeof(nk));
}

