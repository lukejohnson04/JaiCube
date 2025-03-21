
cube_shader : GLuint;

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
}

cube_vertices : [36]Vertex;


VERTICES := Vertex.[
    .{-0.5, -0.5, -0.5,  0.0, 0.0},
    .{0.5, -0.5, -0.5,  1.0, 0.0},
    .{0.5,  0.5, -0.5,  1.0, 1.0},
    .{0.5,  0.5, -0.5,  1.0, 1.0},
    .{-0.5,  0.5, -0.5,  0.0, 1.0},
    .{-0.5, -0.5, -0.5,  0.0, 0.0},

    .{-0.5, -0.5,  0.5,  1.0, 0.0},
    .{0.5, -0.5,  0.5,  0.0, 0.0},
    .{0.5,  0.5,  0.5,  0.0, 1.0},
    .{0.5,  0.5,  0.5,  0.0, 1.0},
    .{-0.5,  0.5,  0.5,  1.0, 1.0},
    .{-0.5, -0.5,  0.5,  1.0, 0.0},

    .{-0.5,  0.5,  0.5,  0.0, 1.0},
    .{-0.5,  0.5, -0.5,  1.0, 1.0},
    .{-0.5, -0.5, -0.5,  1.0, 0.0},
    .{-0.5, -0.5, -0.5,  1.0, 0.0},
    .{-0.5, -0.5,  0.5,  0.0, 0.0},
    .{-0.5,  0.5,  0.5,  0.0, 1.0},

    .{0.5,  0.5,  0.5,   1.0, 1.0},
    .{0.5,  0.5, -0.5,  0.0, 1.0},
    .{0.5, -0.5, -0.5,  0.0, 0.0},
    .{0.5, -0.5, -0.5,  0.0, 0.0},
    .{0.5, -0.5,  0.5,   1.0, 0.0},
    .{0.5,  0.5,  0.5,   1.0, 1.0},

    .{-0.5, -0.5, -0.5,  0.0, 1.0},
    .{0.5, -0.5, -0.5,   1.0, 1.0},
    .{0.5, -0.5,  0.5,   1.0, 0.0},
    .{0.5, -0.5,  0.5,   1.0, 0.0},
    .{-0.5, -0.5,  0.5,  0.0, 0.0},
    .{-0.5, -0.5, -0.5,  0.0, 1.0},

    .{-0.5,  0.5, -0.5,  1.0, 1.0},
    .{0.5,  0.5, -0.5,  0.0, 1.0},
    .{0.5,  0.5,  0.5,  0.0, 0.0},
    .{0.5,  0.5,  0.5,  0.0, 0.0},
    .{-0.5,  0.5,  0.5,  1.0, 0.0},
    .{-0.5,  0.5, -0.5,  1.0, 1.0},
];

intermediate_vao : GLuint;
intermediate_vbo : GLuint;

texture1 : Texture;
texture2 : Texture;
block_texture : Texture;

noise : [CHUNK_SIZE * 16][CHUNK_SIZE * 16]float32;

chunk_vertices : [..]Vertex;


Chunk :: struct {
    data : [CHUNK_SIZE][CHUNK_HEIGHT][CHUNK_SIZE] BLOCK_TYPE;
    world_x, world_z : int;
    solid_vbo: GLuint;
    transparent_vbo: GLuint;
}



WORLD_SIZE :: 16;

CHUNK_SIZE :: 16;
CHUNK_HEIGHT :: 64;

// If a chunk is within the render distance amount of chunks, it will be loaded
// If a chunk leaves the render distance+1 amount of chunks, it will be unloaded
chunks : [WORLD_SIZE][WORLD_SIZE]Chunk;

RENDER_DISTANCE :: 8;

load_chunk :: (chunk: *Chunk) {
    for x: 0..CHUNK_SIZE-1 {
        // reorder data so y level changes the most slowly will increase the speed of generation
        for z: 0..CHUNK_SIZE-1 {
            world_x := chunk.world_x * 16 + x;
            world_z := chunk.world_z * 16 + z;
            noise := perlin2d(xx world_x, xx world_z, 0.05, 3);
            ylevel := cast(int)(noise * CHUNK_HEIGHT);
            waterlevel := 30;

            for y: 0..CHUNK_HEIGHT-1 {
                if y > ylevel {
                    chunk.data[x][y][z] = ifx y < waterlevel then .WATER else .AIR;
                } else if y == ylevel {
                    chunk.data[x][y][z] = .GRASS;
                } else {
                    chunk.data[x][y][z] = .DIRT;
                }
            }
        }
    }
}

load_world :: () {
    for z: 0..15 {
        for x: 0..15 {
            chunks[x][z].world_x = x;
            chunks[x][z].world_z = z;
            load_chunk(*chunks[x][z]);
        }
    }
}

append_chunk_vertices :: (using chunk: *Chunk) {
    // Returns true if the face should be removed
    check_neighbor :: (tile: BLOCK_TYPE, neighbor: BLOCK_TYPE) -> bool {
        if neighbor == .AIR || (neighbor == .WATER && tile != .WATER) {
            return false;
        }
        return true;
        // return (neighbor != .WATER || (neighbor == .WATER && tile == .WATER));
    }

    // Create vertices for the entire world
    for x: 0..CHUNK_SIZE-1 {
        for y: 0..CHUNK_HEIGHT-1 {
            for z: 0..CHUNK_SIZE-1 {
                block := data[x][y][z];
                if block == .AIR continue;

                // check if it is visible
                faces: [6]bool;
                for 0..5 faces[it] = true;

                // back face
                if z > 0 && check_neighbor(block, data[x][y][z-1]) {
                    faces[0] = false;
                }
                // front face
                if z < CHUNK_SIZE-1 && check_neighbor(block, data[x][y][z+1]) {
                    faces[1] = false;
                }
                // left face
                if x > 0 && check_neighbor(block, data[x-1][y][z]) {
                    faces[2] = false;
                }
                // right face
                if x < CHUNK_SIZE-1 && check_neighbor(block, data[x+1][y][z]) {
                    faces[3] = false;
                }
                // top face
                if y > 0 && check_neighbor(block, data[x][y-1][z]) {
                    faces[4] = false;
                }
                // bottom face
                if y < CHUNK_HEIGHT-1 && check_neighbor(block, data[x][y+1][z]) {
                    faces[5] = false;
                }

                for face: 0..5 {
                    if faces[face] == false continue;

                    u0, u1, v0, v1 : float;
                    if block == .DIRT {
                        u0 = 128.0;
                        v0 = 0.0;
                    } else if block == .WATER {
                        u0 = face*32.0;
                        v0 = 32.0;
                    } else {
                        u0 = face*32.0;
                        v0 = 0.0;
                    }

                    u1 = u0 + 32.0;
                    v1 = v0 + 32.0;

                    u0 /= block_texture.width;
                    u1 /= block_texture.width;
                    v0 /= block_texture.height;
                    v1 /= block_texture.height;

                    for pos: 0..5 {
                        vertex := VERTICES[face * 6 + pos];
                        vertex.x += chunk.world_x * 16 + x;
                        vertex.y += y;
                        vertex.z += chunk.world_z * 16 + z;

                        vertex.u = ifx VERTICES[face * 6 + pos].u == 1 then u0 else u1;
                        vertex.v = ifx VERTICES[face * 6 + pos].v == 1 then v0 else v1;
                        
                        // uv value
                        array_add(*chunk_vertices, vertex);
                    }
                }
            }
        }
    }
}

get_loaded_chunks :: () -> [..]*Chunk {
    loaded: [..]*Chunk;
    for x: -RENDER_DISTANCE..RENDER_DISTANCE {
        xpos := cast(int)(camera_position.x / cast(float) CHUNK_SIZE) + x;
        if xpos < 0 || xpos >= WORLD_SIZE {
            continue;
        }
        for z: -RENDER_DISTANCE..RENDER_DISTANCE {
            zpos := cast(int)(camera_position.z / cast(float) CHUNK_SIZE) + z;
            if zpos < 0 || zpos >= WORLD_SIZE {
                continue;
            }
            array_add(*loaded, *chunks[xpos][zpos]);
        }
    }
    return loaded;
}

on_startup :: () {

    // perlin
    for y: 0..CHUNK_SIZE-1 {
        for x: 0..CHUNK_SIZE-1 {
            noise[y][x] = perlin2d(xx x, xx y, 0.05, 3);
        }
    }
    glGenVertexArrays(1, *intermediate_vao);
    glGenBuffers(1, *intermediate_vbo);
    glBindVertexArray(intermediate_vao);

    texture1 = make_texture("data/sprite.png");
    texture2 = make_texture("data/sprite2.png");
    block_texture = make_texture("data/blocks.png");

    cube_shader = create_shader_program("data/shaders/cube.vert", "data/shaders/cube.frag");

    glUseProgram(cube_shader);
    glUniform1i(glGetUniformLocation(cube_shader, "texture1"), 0);


    load_world();
    loaded := get_loaded_chunks();
    chunk_vertices.count = 0;
    for loaded {
        append_chunk_vertices(it);
    }
    glBindBuffer(GL_ARRAY_BUFFER, intermediate_vbo);
    glBufferData(GL_ARRAY_BUFFER, size_of(Vertex) * chunk_vertices.count, chunk_vertices.data, GL_STATIC_DRAW);

    // This is lined up weird... the VBO/VAO is bound at the end of prepare mesh and then adjusted here
    // position attribute
    glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, size_of(float32) * 5, null);
    glEnableVertexAttribArray(0);
    // texture coord attribute
    glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, size_of(float32) * 5, cast(*void)(size_of(float32) * 3));
    glEnableVertexAttribArray(1);


    SDL_SetRelativeMouseMode(SDL_TRUE);
}


rot := 0.0;

BLOCK_TYPE :: enum {
    AIR;
    DIRT;
    GRASS;
    WATER;
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

    if noclip == false {
        // velocity
        player_velocity.y -= 0.85 * FRAME_TIME;
        // check for collision
        PLAYER_HEIGHT :: 3.5;
        player_top := camera_position.y + 0.25;
        player_bottom := player_top - PLAYER_HEIGHT;

        player_chunk_x := cast(int)floor(camera_position.x / cast(float)CHUNK_SIZE);
        player_chunk_z := cast(int)floor(camera_position.z / cast(float)CHUNK_SIZE);
        chunk_x := cast(int)floor(camera_position.x - (player_chunk_x * CHUNK_SIZE));
        chunk_z := cast(int)floor(camera_position.z - (player_chunk_z * CHUNK_SIZE));
        chunk_y := cast(int)ceil(player_bottom);

        if chunk_x >= 0 && chunk_x < CHUNK_SIZE &&
            chunk_y >= 0 && chunk_y < CHUNK_HEIGHT &&
            chunk_z >= 0 && chunk_z < CHUNK_SIZE {
                
            if chunks[player_chunk_x][player_chunk_z].data[chunk_x][chunk_y][chunk_z] != .AIR {
                player_bottom = xx chunk_y;
                camera_position.y = player_bottom + PLAYER_HEIGHT - 0.25;
                player_velocity.y = 0;
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

    /*if false {
        selected_block : Vector3;
        block_highlighted := false;

        // remove block
        ray := camera_position;
        ray_direction := normalize(camera_direction);
        //ray_direction = ray_direction * 0.1;

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

        while true {
            traveled := min(tMaxX, tMaxY, tMaxZ); // how far along ray we are
            if traveled > xx maxDist {
                break;
            }

            if bx < 0 || bx >= CHUNK_SIZE || by < 0 || by >= CHUNK_SIZE || bz < 0 || bz >= CHUNK_SIZE {
                // print ("no col, out of bounds\n");
                // break;
            } else if chunk[bx][by][bz] != .AIR {
                // Found a block
                selected_block = .{xx bx, xx by, xx bz};
                block_highlighted = true;
                // return ( (bx, by, bz), faceHit )
                break;
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

        if input.mouse_just_pressed {
            chunk[xx selected_block.x][xx selected_block.y][xx selected_block.z] = .AIR;
            updated_mesh = true;
        }

        if input.rmouse_just_pressed {
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
                new_block.y < 0 || new_block.y >= CHUNK_SIZE ||
                new_block.z < 0 || new_block.z >= CHUNK_SIZE {

            } else {
                chunk[xx new_block.x][xx new_block.y][xx new_block.z] = .DIRT;
                updated_mesh = true;
            }
        }

        if updated_mesh {
            prepare_mesh();
        }
    }*/

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

    projection = make_projection_matrix(45 * (PI/180), cast(float32)(WINDOW_WIDTH) / cast(float32)(WINDOW_HEIGHT), 0.1, 200);
    model := Matrix4_Identity;

    model_loc := glGetUniformLocation(cube_shader, "model");
    view_loc := glGetUniformLocation(cube_shader, "view");
    glUniformMatrix4fv(view_loc, 1, GL_TRUE, xx *view);
    glUniformMatrix4fv(model_loc, 1, GL_TRUE, xx *model);
    glUniformMatrix4fv(glGetUniformLocation(cube_shader, "projection"), 1, GL_TRUE, xx *projection);

    // Draw blocks
    glBindVertexArray(intermediate_vao);
    glBindBuffer(GL_ARRAY_BUFFER, intermediate_vbo);
    glDrawArrays(GL_TRIANGLES, 0, xx chunk_vertices.count);

    SDL_GL_SwapWindow(window);
    // sleep_till_next_update();
    reset_temporary_storage();
}

#import "Math";
#load "render/render.jai";
