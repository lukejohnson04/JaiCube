
window : *SDL_Window;

main :: () {
    #if OS == .WINDOWS {
        Windows :: #import "Windows";
        Windows.SetProcessDPIAware();

        // Windows is very bad at thread-switching by default unless you do this. Sad.
        Windows.timeBeginPeriod(1);
    }

    if SDL_Init(SDL_INIT_VIDEO | SDL_INIT_AUDIO) != 0 {
        print("Failed to initialize SDL!\n");
        return;
    }

    if TTF_Init() != 0 {
        print("Error: %s\n", TTF_GetError()); 
        return;
    }


    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 3);
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 3);
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, cast(s32) SDL_GL_CONTEXT_PROFILE_CORE);

    window = SDL_CreateWindow("Hello",
                              SDL_WINDOWPOS_UNDEFINED,
                              SDL_WINDOWPOS_UNDEFINED,
                              WINDOW_WIDTH,
                              WINDOW_HEIGHT,
                              SDL_WINDOW_OPENGL | SDL_WINDOW_SHOWN);

    glContext : SDL_GLContext = SDL_GL_CreateContext(window);
    if !glContext {
        print("Error making SDL GL context!\n");
    }


    SDL_GL_MakeCurrent(window, glContext);

    gl_load(*gl);

    glViewport(0, 0, WINDOW_WIDTH, WINDOW_HEIGHT);
    glEnable(GL_BLEND);
    glEnable(GL_DEPTH_TEST);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

    SDL_GL_SetSwapInterval(cast(s32) VSYNC);
    SDL_GL_SetAttribute(SDL_GL_DEPTH_SIZE, 24);
    SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1);
    screenSurface := SDL_GetWindowSurface(window);

    on_startup();

    running := true;

    while running {
        poll_input(*running);
        update_and_render(*running);
    }

    SDL_DestroyWindow(window);
    SDL_Quit();
}

WINDOW_WIDTH :: 1280;
WINDOW_HEIGHT :: 720;
VSYNC :: true;

#import "Windows";
#import "Basic";
#import "String";
#import "SDL";
#import "SDL_ttf";
#import "GL";
#import "File";
#import "Simp";
#import "Random";

#import "freetype-2.12.1";

#load "source/math.jai";
#load "source/input.jai";
#load "source/game.jai";
#load "source/render/shader.jai";
#load "source/render/text.jai";
#load "source/perlin.jai";