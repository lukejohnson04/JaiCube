
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

Chunk :: struct {
    data : [CHUNK_HEIGHT][CHUNK_SIZE][CHUNK_SIZE] BLOCK_TYPE;
    world_x, world_z : s16;

    solid_vao: GLuint;
    solid_vbo: GLuint;
    vertex_count: int;
    transparent_vao: GLuint;
    transparent_vbo: GLuint;
    transparent_vertex_count: int;
    transparent_vertices: [..]Vertex;
}

temp_vertex_buffer: [..]Vertex;

get_block :: (chunk: *Chunk, x: int, y: int, z: int) -> BLOCK_TYPE {
    return chunk.data[y][x][z];
}

set_block :: (chunk: *Chunk, x: int, y: int, z: int, block: BLOCK_TYPE) {
    chunk.data[y][x][z] = block;
}


WORLD_SIZE :: 16;

CHUNK_SIZE :: 16;
CHUNK_HEIGHT :: 128;

// If a chunk is within the render distance amount of chunks, it will be loaded
// If a chunk leaves the render distance+1 amount of chunks, it will be unloaded
// chunks : [WORLD_SIZE][WORLD_SIZE]Chunk;
loaded_chunks : [..]Chunk;

RENDER_DISTANCE :: 12;


generate_chunk :: (chunk: *Chunk) {
    for x: 0..CHUNK_SIZE-1 {
        // reorder data so y level changes the most slowly will increase the speed of generation
        for z: 0..CHUNK_SIZE-1 {
            world_x : float64 = xx (chunk.world_x * 16 + x);
            world_z : float64 = xx (chunk.world_z * 16 + z);
            noise := perlin2d(world_x, world_z, 0.015, 8);
            special_noise := perlin2d(world_x+1000, world_z+1000, 0.9, 8);
            y_level := cast(int)(noise * CHUNK_HEIGHT);
            water_level :: 30;

            // fill w dirt
            for 0..y_level-1 {
                set_block(chunk, x, it, z, .DIRT);
            }
            // Set top to grass
            set_block(chunk, x, y_level, z, .GRASS);
            if y_level > water_level && special_noise > 0.78 && x != 0 && x != CHUNK_SIZE-1 && z != 0 && z != CHUNK_SIZE-1 {
                set_block(chunk, x, y_level+1, z, .LOG);
                set_block(chunk, x, y_level+2, z, .LOG);
                set_block(chunk, x, y_level+3, z, .LOG);
                set_block(chunk, x, y_level+4, z, .LOG);
                
                // set_block(chunk, x, y_level+5, z, .LEAF);
                for sub_y: (y_level+5)..(y_level+6) {
                    for sub_x: x-1..x+1 {
                        for sub_z: z-1..z+1 {
                            set_block(chunk, sub_x, sub_y, sub_z, .LEAF);
                        }
                    }
                }

                set_block(chunk, x, y_level+6, z, .LEAF);
                set_block(chunk, x, y_level+7, z, .LEAF);
            }
            // fill w water to water level
            for y_level+1..water_level {
                set_block(chunk, x, it, z, .WATER);
            }
        }
    }
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

generate_chunk_vertices :: (using chunk: *Chunk) {
    vertex_count = 0;
    transparent_vertex_count = 0;
    transparent_vertices.count = 0;
    temp_vertex_buffer.count = 0;
    
    l, r, u, d: *Chunk;
    
    for loaded_chunks {
        if it.world_x == chunk.world_x - 1 && it.world_z == chunk.world_z {
            l = *it;
            continue;
        }
        if it.world_x == chunk.world_x + 1 && it.world_z == chunk.world_z {
            r = *it;
            continue;
        }
        if it.world_x == chunk.world_x && it.world_z == chunk.world_z + 1 {
            u = *it;
            continue;
        }
        if it.world_x == chunk.world_x && it.world_z == chunk.world_z - 1 {
            d = *it;
            continue;
        }

        if l && r && u && d break;
    }


    check_face :: (neighbor: BLOCK_TYPE, block: BLOCK_TYPE) -> bool {
        if block == .LEAF || neighbor == .LEAF return false;
        if neighbor == .AIR || (block != .WATER && neighbor == .WATER) {
            return false;
        }
        return true;
    }
    
    // Create vertices for the entire world
    world_coord_x := world_x * 16;
    world_coord_z := world_z * 16;

    for x: 0..CHUNK_SIZE-1 {
        for z: 0..CHUNK_SIZE-1 {
            for y: 0..CHUNK_HEIGHT-1 {
                faces: [6]bool;
                block := get_block(chunk, x, y, z);
                if block == .AIR continue;

                // check if it's visible
                // back face
                if z > 0 {
                    faces[0] = check_face(get_block(chunk, x, y, z-1), block);
                } else if d {
                    faces[0] = check_face(get_block(d, x, y, CHUNK_SIZE-1), block);
                }
                // front face
                if z < CHUNK_SIZE-1 {
                    faces[1] = check_face(get_block(chunk, x, y, z+1), block);
                } else if u {
                    faces[1] = check_face(get_block(u, x, y, 0), block);
                }
                // left face
                if x > 0 {
                    faces[2] = check_face(get_block(chunk, x-1, y, z), block);
                } else if l {
                    faces[2] = check_face(get_block(l, CHUNK_SIZE-1, y, z), block);
                }
                // rightface
                if x < CHUNK_SIZE-1 {
                    faces[3] = check_face(get_block(chunk, x+1, y, z), block);
                } else if r {
                    faces[3] = check_face(get_block(r, 0, y, z), block);
                }
                // up face
                if y > 0 {
                    faces[4] = check_face(get_block(chunk, x, y-1, z), block);
                } if y < CHUNK_HEIGHT-1 {
                    faces[5] = check_face(get_block(chunk, x, y+1, z), block);
                }

                for face: 0..5 {
                    if faces[face] == true continue;
                    light_level := ifx (face == 0 || face == 2) then 0.75 else 1.0;

                    u0, u1, v0, v1 : float;
                    u0 = block_info[block].u;
                    if block_info[block].multiple_faces != 0 then u0 += face * block_info[block].size_x;
                    v0 = block_info[block].v;

                    u1 = u0 + block_info[block].size_x;
                    v1 = v0 + block_info[block].size_y;

                    base_x := world_coord_x + x;
                    base_z := world_coord_z + z;
                    for pos: 0..5 {
                        vertex := VERTICES[face * 6 + pos];
                        vertex.x += base_x;
                        vertex.y += y;
                        vertex.z += base_z;

                        vertex.u = ifx VERTICES[face * 6 + pos].u == 1 then u0 else u1;
                        vertex.v = ifx VERTICES[face * 6 + pos].v == 1 then v0 else v1;
                        
                        vertex.light_level = light_level;
                        if block == .WATER || block == .LEAF {
                            array_add(*transparent_vertices, vertex);
                        } else {
                            vertex.light_level *= ifx y >= 30 then 1 else pow(0.8, xx (30 - y));
                            array_add(*temp_vertex_buffer, vertex);
                        }
                    }
                }
            }
        }
    }
    vertex_count = temp_vertex_buffer.count;
    transparent_vertex_count = transparent_vertices.count;

    if glIsBuffer(chunk.solid_vbo) == GL_FALSE {
        glGenBuffers(1, *chunk.solid_vbo);
    } if glIsVertexArray(chunk.solid_vao) == GL_FALSE {
        glGenVertexArrays(1, *chunk.solid_vao);
    }
    glBindBuffer(GL_ARRAY_BUFFER, chunk.solid_vbo);
    glBufferData(GL_ARRAY_BUFFER, size_of(Vertex) * temp_vertex_buffer.count, temp_vertex_buffer.data, GL_STATIC_DRAW);

    glBindVertexArray(chunk.solid_vao);
    // position attribute
    glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, size_of(float32) * 6, null);
    glEnableVertexAttribArray(0);
    // texture coord attribute
    glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, size_of(float32) * 6, cast(*void)(size_of(float32) * 3));
    glEnableVertexAttribArray(1);
    // light attribute
    glVertexAttribPointer(2, 1, GL_FLOAT, GL_FALSE, size_of(float32) * 6, cast(*void)(size_of(float32) * 5));
    glEnableVertexAttribArray(2);

    if glIsBuffer(chunk.transparent_vbo) == GL_FALSE {
        glGenBuffers(1, *chunk.transparent_vbo);
    } if glIsVertexArray(chunk.transparent_vao) == GL_FALSE {
        glGenVertexArrays(1, *chunk.transparent_vao);
    }
    glBindBuffer(GL_ARRAY_BUFFER, chunk.transparent_vbo);
    glBufferData(GL_ARRAY_BUFFER, size_of(Vertex) * chunk.transparent_vertices.count, chunk.transparent_vertices.data, GL_STATIC_DRAW);

    glBindVertexArray(chunk.transparent_vao);
    // position attribute
    glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, size_of(float32) * 6, null);
    glEnableVertexAttribArray(0);
    // texture coord attribute
    glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, size_of(float32) * 6, cast(*void)(size_of(float32) * 3));
    glEnableVertexAttribArray(1);
    // light attribute
    glVertexAttribPointer(2, 1, GL_FLOAT, GL_FALSE, size_of(float32) * 6, cast(*void)(size_of(float32) * 5));
    glEnableVertexAttribArray(2);

    array_reset(*transparent_vertices);
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


    chunk_x := cast(int)floor((camera_position.x) / CHUNK_SIZE);
    chunk_z := cast(int)floor((camera_position.z) / CHUNK_SIZE);
    for x: (chunk_x-RENDER_DISTANCE)..(chunk_x+RENDER_DISTANCE) {
        // xpos := cast(s16)((camera_position.x / cast(float) CHUNK_SIZE) + x);
        for z: (chunk_z-RENDER_DISTANCE)..(chunk_z+RENDER_DISTANCE) {
            // zpos := cast(s16)((camera_position.z / cast(float) CHUNK_SIZE) + z);

            chunk : *Chunk = array_add(*loaded_chunks);
            chunk.world_x = xx x;
            chunk.world_z = xx z;
            generate_chunk(chunk);
        }
    }


    for loaded_chunks {
        generate_chunk_vertices(*it);
    }

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
    new_chunks : [..]*Chunk;
    new_chunks.allocator = temp;
    for x: (chunk_x-RENDER_DISTANCE)..(chunk_x+RENDER_DISTANCE) {
        for z: (chunk_z-RENDER_DISTANCE)..(chunk_z+RENDER_DISTANCE) {
            // see if chunk exists
            for loaded_chunks {
                if it.world_x == x && it.world_z == z {
                    continue z;
                }
            }

            chunk : *Chunk = array_add(*loaded_chunks);
            chunk.world_x = xx x;
            chunk.world_z = xx z;
            generate_chunk(chunk);
            array_add(*new_chunks, chunk);
        }
    }

    for new_chunks {
        generate_chunk_vertices(it);
    }

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
        glDrawArrays(GL_TRIANGLES, 0, xx it.vertex_count);
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
        glDrawArrays(GL_TRIANGLES, 0, xx it.transparent_vertex_count);
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

#load "render/render.jai";
