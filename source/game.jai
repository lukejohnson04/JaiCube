
cube_shader : GLuint;
water_shader : GLuint;

make_texture :: (path: string) -> Texture {
    result : Texture;
    texture_load_from_file(*result, path);
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    return result;
}


FRAME_TIME : float32 : 1.0 / 60.0;
last_frame_time : s64 = 0;
global_clock : s64 = 0;

sleep_till_next_update :: () {
    delay_time := last_frame_time + (FRAME_TIME * 1000) - SDL_GetTicks();
    SDL_Delay(cast(u32) ifx delay_time > 0 then delay_time);
    global_clock = SDL_GetTicks();
    last_frame_time = global_clock;
}

Vertex :: struct {
    x, y, z: float32;
    u, v: float32;
    light_level: float32;
}

cube_vertices : [36]Vertex;


VERTICES := Vertex.[
    .{-0.5, -0.5, -0.5,  0.0, 0.0, 1.0},
    .{0.5, -0.5, -0.5,  1.0, 0.0, 1.0},
    .{0.5,  0.5, -0.5,  1.0, 1.0, 1.0},
    .{0.5,  0.5, -0.5,  1.0, 1.0, 1.0},
    .{-0.5,  0.5, -0.5,  0.0, 1.0, 1.0},
    .{-0.5, -0.5, -0.5,  0.0, 0.0, 1.0},

    .{-0.5, -0.5,  0.5,  1.0, 0.0, 1.0},
    .{0.5, -0.5,  0.5,  0.0, 0.0, 1.0},
    .{0.5,  0.5,  0.5,  0.0, 1.0, 1.0},
    .{0.5,  0.5,  0.5,  0.0, 1.0, 1.0},
    .{-0.5,  0.5,  0.5,  1.0, 1.0, 1.0},
    .{-0.5, -0.5,  0.5,  1.0, 0.0, 1.0},

    .{-0.5,  0.5,  0.5,  0.0, 1.0, 1.0},
    .{-0.5,  0.5, -0.5,  1.0, 1.0, 1.0},
    .{-0.5, -0.5, -0.5,  1.0, 0.0, 1.0},
    .{-0.5, -0.5, -0.5,  1.0, 0.0, 1.0},
    .{-0.5, -0.5,  0.5,  0.0, 0.0, 1.0},
    .{-0.5,  0.5,  0.5,  0.0, 1.0, 1.0},

    .{0.5,  0.5,  0.5,   1.0, 1.0, 1.0},
    .{0.5,  0.5, -0.5,  0.0, 1.0, 1.0},
    .{0.5, -0.5, -0.5,  0.0, 0.0, 1.0},
    .{0.5, -0.5, -0.5,  0.0, 0.0, 1.0},
    .{0.5, -0.5,  0.5,   1.0, 0.0, 1.0},
    .{0.5,  0.5,  0.5,   1.0, 1.0, 1.0},

    .{-0.5, -0.5, -0.5,  0.0, 1.0, 1.0},
    .{0.5, -0.5, -0.5,   1.0, 1.0, 1.0},
    .{0.5, -0.5,  0.5,   1.0, 0.0, 1.0},
    .{0.5, -0.5,  0.5,   1.0, 0.0, 1.0},
    .{-0.5, -0.5,  0.5,  0.0, 0.0, 1.0},
    .{-0.5, -0.5, -0.5,  0.0, 1.0, 1.0},

    .{-0.5,  0.5, -0.5,  1.0, 1.0, 1.0},
    .{0.5,  0.5, -0.5,  0.0, 1.0, 1.0},
    .{0.5,  0.5,  0.5,  0.0, 0.0, 1.0},
    .{0.5,  0.5,  0.5,  0.0, 0.0, 1.0},
    .{-0.5,  0.5,  0.5,  1.0, 0.0, 1.0},
    .{-0.5,  0.5, -0.5,  1.0, 1.0, 1.0}
];

intermediate_vao : GLuint;
intermediate_vbo : GLuint;

texture1 : Texture;
texture2 : Texture;
block_texture : Texture;
water_noise_texture : Texture;

noise : [CHUNK_SIZE * 16][CHUNK_SIZE * 16]float32;

get_block :: (chunk: *Chunk, x: int, y: int, z: int) -> BLOCK_TYPE {
    return chunk.data[y][x][z];
}

set_block :: (chunk: *Chunk, x: int, y: int, z: int, block: BLOCK_TYPE) {
    chunk.data[y][x][z] = block;
}


WORLD_SIZE :: 16;

CHUNK_SIZE :: 16;
CHUNK_HEIGHT :: 96;

// If a chunk is within the render distance amount of chunks, it will be loaded
// If a chunk leaves the render distance+1 amount of chunks, it will be unloaded
// chunks : [WORLD_SIZE][WORLD_SIZE]Chunk;
loaded_chunks : [..]Chunk;

RENDER_DISTANCE :: 32;


#import "System";
#import "Pool";
// Threading
generation_group, vertices_group: Thread_Group;
pool: Pool;

init_generation_thread_group :: () {
    num_cpus := get_number_of_processors();

    assert(num_cpus >= 1);
    #if (OS == .WINDOWS) || (OS == .LINUX) {
        // This routine reports hyperthreads, so, divide by two, because of Intel marketing.
        num_cpus /= 2;
    }

    num_threads := max(num_cpus - 1, 2);
    init(*generation_group, num_threads, generation_proc);
    generation_group.name = "Generation";
    generation_group.logging = false;
}

init_vertices_thread_group :: () {
    num_cpus := get_number_of_processors();

    assert(num_cpus >= 1);
    #if (OS == .WINDOWS) || (OS == .LINUX) {
        // This routine reports hyperthreads, so, divide by two, because of Intel marketing.
        num_cpus /= 2;
    }

    num_threads := max(num_cpus - 1, 2);
    init(*vertices_group, num_threads, vertices_proc);
    vertices_group.name = "Vertices";
    vertices_group.logging = false;
}


generation_proc :: (group: *Thread_Group, thread: *Thread, work: *void) -> Thread_Continue_Status {
    chunk := cast(*Chunk) work;
    generate_chunk_terrain(chunk);
    return .CONTINUE;
}

vertices_proc :: (group: *Thread_Group, thread: *Thread, work: *void) -> Thread_Continue_Status {
    chunk := cast(*Chunk) work;
    generate_chunk_vertices(chunk);
    return .CONTINUE;
}

BLOCK_TEXTURE_INFO :: struct {
    u: float32;
    v: float32;
    size_x: float32;
    size_y: float32;
    multiple_faces: int;
}

block_info : [32]BLOCK_TEXTURE_INFO = #run generate_block_texture_info();

BLOCK_TEXTURE_WIDTH :: 256;
BLOCK_TEXTURE_HEIGHT :: 256;

generate_block_texture_info :: () -> [32]BLOCK_TEXTURE_INFO {
    create_block_info :: (start_x: float32, start_y: float32, multiple_faces: int, size_x: float32 = 32.0, size_y: float32 = 32.0) -> BLOCK_TEXTURE_INFO {
        res: BLOCK_TEXTURE_INFO;
        res.u = start_x / BLOCK_TEXTURE_WIDTH;
        res.v = start_y / BLOCK_TEXTURE_HEIGHT;
        // IMPORTANT: THIS MEANS THE BLOCK TEXTURE WIDTH AND HEIGHT MUST BE THE SAME!!!
        res.size_x = size_x / BLOCK_TEXTURE_WIDTH;
        res.size_y = size_y / BLOCK_TEXTURE_HEIGHT;
        res.multiple_faces = multiple_faces;
        return res;
    }

    info: [32]BLOCK_TEXTURE_INFO;
    info[BLOCK_TYPE.DIRT]       =   create_block_info(128, 0, 0);
    info[BLOCK_TYPE.SAND]       =   create_block_info(0, 64, 0);
    info[BLOCK_TYPE.WATER]      =   create_block_info(0, 32, 1);
    info[BLOCK_TYPE.GRASS]      =   create_block_info(0, 0, 1);
    info[BLOCK_TYPE.LOG]        =   create_block_info(0, 96, 1);
    info[BLOCK_TYPE.LEAF]        =   create_block_info(0, 128, 0);
    return info;
}

on_startup :: () {
    // perlin
    glGenVertexArrays(1, *intermediate_vao);
    glGenBuffers(1, *intermediate_vbo);
    glBindVertexArray(intermediate_vao);

    texture1 = make_texture("data/sprite.png");
    texture2 = make_texture("data/sprite2.png");
    block_texture = make_texture("data/blocks.png");
    water_noise_texture = make_texture("data/noise.png");

    cube_shader = create_shader_program("data/shaders/cube.vert", "data/shaders/cube.frag");
    water_shader = create_shader_program("data/shaders/water.vert", "data/shaders/water.frag");

    glUseProgram(water_shader);
    glUniform1i(glGetUniformLocation(water_shader, "texture1"), 0);
    glUniform1i(glGetUniformLocation(water_shader, "noise"), 1);

    glUseProgram(cube_shader);
    glUniform1i(glGetUniformLocation(cube_shader, "texture1"), 0);


    init_generation_thread_group();
    start(*generation_group);

    chunk_x := cast(int)floor((camera_position.x) / CHUNK_SIZE);
    chunk_z := cast(int)floor((camera_position.z) / CHUNK_SIZE);
    iter := 0;
    for x: (chunk_x-RENDER_DISTANCE)..(chunk_x+RENDER_DISTANCE) {
        for z: (chunk_z-RENDER_DISTANCE)..(chunk_z+RENDER_DISTANCE) {
            defer iter += 1;
            // Generate chunk
            chunk : *Chunk = array_add(*loaded_chunks);
            chunk.world_x = xx x;
            chunk.world_z = xx z;
        }
    }

    for loaded_chunks {
        add_work(*generation_group, *it, tprint("Work item %", it_index));
    }

    work_remaining := iter;
    while work_remaining > 0 {
        SDL_Delay(10);
        results := get_completed_work(*generation_group);
        work_remaining -= results.count;
    }
    shutdown(*generation_group);

    print("Generating vertices\n");

    init_vertices_thread_group();
    start(*vertices_group);
    
    work_remaining = loaded_chunks.count;
    for loaded_chunks {
        add_work(*vertices_group, *it, tprint("Work item %", it_index));
    }
    
    while work_remaining > 0 {
        SDL_Delay(10);
        results := get_completed_work(*vertices_group);
        work_remaining -= results.count;
    }
    print("Finished generation, bunch of opengl incoming!\n");

    for loaded_chunks {
        generate_buffer_from_chunk(*it);
    }

    shutdown(*vertices_group);

    SDL_SetRelativeMouseMode(SDL_TRUE);
}


BLOCK_TYPE :: enum u8 {
    AIR :: 0;
    DIRT;
    GRASS;
    WATER;
    SAND;
    LOG;
    LEAF;
}

camera_position := Vector3.{50, 50, 50};
camera_front := Vector3.{0, 0, -1};
camera_up := Vector3.{0, 1, 0};
camera_right := Vector3.{1, 0, 0};

yaw := -90.0;
pitch := 0.0;

timer := 0.0;

noclip := true;
player_velocity : Vector3;


update_and_render :: (running : *bool) {
    if input.is_pressed[SDL_SCANCODE_ESCAPE] {
        running.* = false;
    }

    timer += FRAME_TIME;

    camera_speed := 0.1;
    // Input
    move_forward := camera_front;
    move_forward.y = 0;
    move_forward = normalize(move_forward);
    if input.is_pressed[SDL_SCANCODE_W] {
        camera_position += camera_speed * move_forward;
    } if input.is_pressed[SDL_SCANCODE_S] {
        camera_position -= camera_speed * move_forward;
    } if input.is_pressed[SDL_SCANCODE_A] {
        camera_position -= normalize(cross_product(move_forward, camera_up)) * camera_speed;
    } if input.is_pressed[SDL_SCANCODE_D] {
        camera_position += normalize(cross_product(move_forward, camera_up)) * camera_speed;
    }

    if input.is_pressed[SDL_SCANCODE_SPACE] {
        camera_position += camera_speed * camera_up;
    } if input.is_pressed[SDL_SCANCODE_LSHIFT] {
        camera_position += camera_speed * -camera_up;
    }

    if input.just_pressed[SDL_SCANCODE_GRAVE] {
        noclip = !noclip;
        player_velocity = .{0,0,0};
    }

    // Goal of this code:
    // If a chunk is within RENDER DISTANCE chunks, we want to be sure it is loaded
    // If a chunk is outside of RENDER DISTANCE + 1 chunks, we want to be sure it is unloaded
    chunk_x := cast(int)floor((camera_position.x) / CHUNK_SIZE);
    chunk_z := cast(int)floor((camera_position.z) / CHUNK_SIZE);

    added_or_removed := false;
    // Unload chunks
    for loaded_chunks {
        // generic distance
        distance_x := abs(chunk_x - it.world_x);
        distance_z := abs(chunk_z - it.world_z);
        distance := max(distance_x, distance_z);
        if distance > RENDER_DISTANCE + 1 {
            remove it;
        }
    }

    // Add chunks
    // new_chunks : [..]*Chunk;
    // new_chunks.allocator = temp;
    // for x: (chunk_x-RENDER_DISTANCE)..(chunk_x+RENDER_DISTANCE) {
    //     for z: (chunk_z-RENDER_DISTANCE)..(chunk_z+RENDER_DISTANCE) {
    //         // see if chunk exists
    //         for loaded_chunks {
    //             if it.world_x == x && it.world_z == z {
    //                 continue z;
    //             }
    //         }

    //         chunk : *Chunk = array_add(*loaded_chunks);
    //         chunk.world_x = xx x;
    //         chunk.world_z = xx z;
    //         generate_chunk(chunk);
    //         array_add(*new_chunks, chunk);
    //     }
    // }

    // for new_chunks {
    //     generate_chunk_vertices(it);
    // }

    if noclip == false {
        // velocity
        player_velocity.y -= 0.85 * FRAME_TIME;
        // check for collision
        PLAYER_HEIGHT :: 3.5;
        player_top := camera_position.y + 0.25;
        player_bottom := player_top - PLAYER_HEIGHT;

        player_chunk_x := cast(s16)floor(camera_position.x / cast(float)CHUNK_SIZE);
        player_chunk_z := cast(s16)floor(camera_position.z / cast(float)CHUNK_SIZE);
        chunk_x := cast(s16)floor(camera_position.x - (player_chunk_x * CHUNK_SIZE));
        chunk_z := cast(s16)floor(camera_position.z - (player_chunk_z * CHUNK_SIZE));
        chunk_y := cast(s16)ceil(player_bottom);

        if chunk_x >= 0 && chunk_x < CHUNK_SIZE &&
            chunk_y >= 0 && chunk_y < CHUNK_HEIGHT &&
            chunk_z >= 0 && chunk_z < CHUNK_SIZE {

            chunk : *Chunk;
            for loaded_chunks {
                if it.world_x == player_chunk_x && it.world_z == player_chunk_z {
                    chunk = *it;
                    break;
                }
            }
            if chunk != null {
                if get_block(chunk, chunk_x, chunk_y, chunk_z) != .AIR {
                    player_bottom = xx chunk_y;
                    camera_position.y = player_bottom + PLAYER_HEIGHT - 0.25;
                    player_velocity.y = 0;
                }
            }
        }

        camera_position += player_velocity;
    }

    mouse_sensitivity := 0.25;
    yaw += input.mouse_motion.x * mouse_sensitivity;
    pitch -= input.mouse_motion.y * mouse_sensitivity;
    if pitch > 89   pitch = 89;
    if pitch < -89  pitch = -89;
    
    camera_direction : Vector3;
    camera_direction.x = cos(radians(yaw)) * cos(radians(pitch));
    camera_direction.y = sin(radians(pitch));
    camera_direction.z = sin(radians(yaw)) * cos(radians(pitch));
    camera_front = normalize(camera_direction);


    // This is all code for raytracing block collision. It's all kinda garbage and stolen. Will refactor later!
    selected_block : Vector3;
    block_highlighted := false;

    // remove block
    ray := camera_position;
    ray_direction := normalize(camera_direction);
    
    bx : int = xx floor(ray.x);
    by : int = xx floor(ray.y);
    bz : int = xx floor(ray.z);

    stepX := ifx ray_direction.x >= 0 then 1 else -1;
    stepY := ifx ray_direction.y >= 0 then 1 else -1;
    stepZ := ifx ray_direction.z >= 0 then 1 else -1;

    tDeltaX : float32 = ifx (ray_direction.x == 0) then 999999 else abs(1 / ray_direction.x);
    tDeltaY : float32 = ifx (ray_direction.y == 0) then 999999 else abs(1 / ray_direction.y);
    tDeltaZ : float32 = ifx (ray_direction.z == 0) then 999999 else abs(1 / ray_direction.z);

    nextBoundaryX := ifx (stepX > 0) then (bx + 1) else bx;   // If direction is +X, boundary is at the next integer block edge
    nextBoundaryY := ifx (stepY > 0) then (by + 1) else by;
    nextBoundaryZ := ifx (stepZ > 0) then (bz + 1) else bz;

    tMaxX := ifx (ray_direction.x == 0) then 999999 else ( (nextBoundaryX - ray.x) / ray_direction.x );
    tMaxY := ifx (ray_direction.y == 0) then 999999 else ( (nextBoundaryY - ray.y) / ray_direction.y );
    tMaxZ := ifx (ray_direction.z == 0) then 999999 else ( (nextBoundaryZ - ray.z) / ray_direction.z );

    maxDist := 10;

    FACE_HIT :: enum {
        BACK;
        FRONT;
        LEFT;
        RIGHT;
        TOP;
        BOTTOM;
        NONE;
    }
    faceHit := FACE_HIT.NONE;

    selected_chunk : *Chunk = null;

    while true {
        traveled := min(tMaxX, tMaxY, tMaxZ); // how far along ray we are
        if traveled > xx maxDist {
            break;
        }
        
        if by < CHUNK_HEIGHT && by > 0 {
            // Chunk of the block
            chunk_x := cast(s16)floor(bx / 16.0);
            chunk_z := cast(s16)floor(bz / 16.0);

            chunk : *Chunk;
            for loaded_chunks {
                if it.world_x == chunk_x && it.world_z == chunk_z {
                    chunk = *it;
                    break;
                }
            }
            if chunk == null continue;

            block_pos_x := bx - (chunk_x*CHUNK_SIZE);
            block_pos_z := bz - (chunk_z*CHUNK_SIZE);

            if get_block(chunk, block_pos_x, by, block_pos_z) != .AIR {
                // Found a block
                selected_chunk = chunk;
                selected_block = .{xx block_pos_x, xx by, xx block_pos_z};
                block_highlighted = true;
                break;
            }
        }

        if tMaxX < tMaxY && tMaxX < tMaxZ {
            bx += stepX;
            tMaxX += tDeltaX;
            faceHit = ifx stepX > 0 then .LEFT else .RIGHT;
        } else if tMaxY < tMaxZ {
            by += stepY;
            tMaxY += tDeltaY;
            faceHit = ifx (stepY > 0) then .BOTTOM else .TOP;
        } else {
            bz += stepZ;
            tMaxZ += tDeltaZ;
            faceHit = ifx (stepZ > 0) then .BACK else .FRONT;
        }
    }

    updated_mesh := false;

    if input.mouse_just_pressed && block_highlighted {
        // Find current chunk
        set_block(selected_chunk, xx selected_block.x, xx selected_block.y, xx selected_block.z, .AIR);
        updated_mesh = true;
    }

    if input.rmouse_just_pressed && block_highlighted {
        new_block := selected_block;
        if faceHit == {
            case .LEFT; new_block.x -= 1;
            case .RIGHT; new_block.x += 1;
            case .BACK; new_block.z -= 1;
            case .FRONT; new_block.z += 1;
            case .TOP; new_block.y += 1;
            case .BOTTOM; new_block.y -= 1;
        }
        if new_block.x < 0 || new_block.x >= CHUNK_SIZE ||
            new_block.y < 0 || new_block.y >= CHUNK_HEIGHT ||
            new_block.z < 0 || new_block.z >= CHUNK_SIZE {

        } else {
            set_block(selected_chunk, xx new_block.x, xx new_block.y, xx new_block.z, .DIRT);
            updated_mesh = true;
        }
    }

    if updated_mesh {
        generate_chunk_vertices(selected_chunk);
    }

    // Render begin
    glClearColor(0.35, 0.5, 0.9, 1.0);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, block_texture.gl_handle);
    glUseProgram(cube_shader);

    view := Matrix4_Identity;
    projection := Matrix4_Identity;

    radius := 0.01;
    camX := sin(timer) * radius;
    camZ := cos(timer) * radius;
    view = make_look_at_matrix(camera_position, camera_position + camera_front, camera_up, false);

    projection = make_projection_matrix(45 * (PI/180), cast(float32)(WINDOW_WIDTH) / cast(float32)(WINDOW_HEIGHT), 0.1, 1000);
    model := Matrix4_Identity;

    model_loc := glGetUniformLocation(cube_shader, "model");
    view_loc := glGetUniformLocation(cube_shader, "view");
    glUniformMatrix4fv(view_loc, 1, GL_TRUE, xx *view);
    glUniformMatrix4fv(model_loc, 1, GL_TRUE, xx *model);
    glUniformMatrix4fv(glGetUniformLocation(cube_shader, "projection"), 1, GL_TRUE, xx *projection);

    // Draw blocks
    glDepthMask(GL_TRUE);
    glEnable(GL_DEPTH_TEST);
    for loaded_chunks {
        glBindVertexArray(it.solid_vao);
        glBindBuffer(GL_ARRAY_BUFFER, it.solid_vbo);
        glDrawArrays(GL_TRIANGLES, 0, xx it.vertices.count);
    }

    glActiveTexture(GL_TEXTURE1);
    glBindTexture(GL_TEXTURE_2D, water_noise_texture.gl_handle);
    glUseProgram(water_shader);
    glUniformMatrix4fv(glGetUniformLocation(water_shader, "model"), 1, GL_TRUE, xx *model);
    glUniformMatrix4fv(glGetUniformLocation(water_shader, "view"), 1, GL_TRUE, xx *view);
    glUniformMatrix4fv(glGetUniformLocation(water_shader, "projection"), 1, GL_TRUE, xx *projection);
    glUniform1f(glGetUniformLocation(water_shader, "time"), timer);

    // Make this false for true water!
    glDepthMask(GL_TRUE);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    for loaded_chunks {
        glBindVertexArray(it.transparent_vao);
        glBindBuffer(GL_ARRAY_BUFFER, it.transparent_vbo);
        glDrawArrays(GL_TRIANGLES, 0, xx it.transparent_vertices.count);
    }
    glDepthMask(GL_TRUE);

    SDL_GL_SwapWindow(window);
    // sleep_till_next_update();
    reset_temporary_storage();
}

#import "Math";
Hash_Table :: #import "Hash_Table";
Hash :: #import "Hash";
#poke_name Hash_Table operator==;
#import "Thread";

#load "render/render.jai";
#load "chunk.jai";