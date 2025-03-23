
Chunk :: struct {
    data : [CHUNK_HEIGHT][CHUNK_SIZE][CHUNK_SIZE] BLOCK_TYPE;
    world_x, world_z : s16;

    solid_vao: GLuint;
    solid_vbo: GLuint;
    transparent_vao: GLuint;
    transparent_vbo: GLuint;
    transparent_vertices: [..]Vertex;
    vertices: [..]Vertex;
}


generate_chunk_terrain :: (chunk: *Chunk) {
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

generate_buffer_from_chunk :: (using chunk: *Chunk) {
    if glIsBuffer(chunk.solid_vbo) == GL_FALSE {
        glGenBuffers(1, *chunk.solid_vbo);
    } if glIsVertexArray(chunk.solid_vao) == GL_FALSE {
        glGenVertexArrays(1, *chunk.solid_vao);
    }
    glBindBuffer(GL_ARRAY_BUFFER, chunk.solid_vbo);
    glBufferData(GL_ARRAY_BUFFER, size_of(Vertex) * vertices.count, vertices.data, GL_STATIC_DRAW);

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
    glBufferData(GL_ARRAY_BUFFER, size_of(Vertex) * transparent_vertices.count, transparent_vertices.data, GL_STATIC_DRAW);

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
}

generate_chunk_vertices :: (using chunk: *Chunk) {
    vertex_buffer: [..]Vertex;

    vertices.count = 0;
    transparent_vertices.count = 0;
    
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
                            array_add(*vertices, vertex);
                        }
                    }
                }
            }
        }
    }
}

