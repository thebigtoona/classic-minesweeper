package minesweeper

import "core:c"
import "core:fmt"
import "core:strconv"
import "core:strings"
import "core:time"
import rl "vendor:raylib"

INITAL_SCREEN_SIZE: [2]c.int = {480, 540}

GRID_SIZE: int = 40
GRID_BOUND_UPPER_LEFT: [2]c.int = {40, 100}
GRID_RECT_SIZE: [2]c.int = {400, 400}
GRID_WIDTH: int = 10

MAX_BOMBS: int = 10
FLAG_COUNT_ICON_POSITION: rl.Vector2 = {390, 60}
FLAG_COUNT := MAX_BOMBS

CELL_FONT_SIZE: i32 = 16
LABEL_FONT_SIZE: i32 = 20
HEADER_FONT_SIZE: i32 = 40

SCREEN :: enum {
	Start,
	Game,
	Controls,
}

main :: proc() {
	// ****
	// INITIALIZATION STEP 
	// ****

	// init window
	rl.InitWindow(INITAL_SCREEN_SIZE.x, INITAL_SCREEN_SIZE.y, "Minesweeper")
	defer rl.CloseWindow()

	// set frame rate
	rl.SetTargetFPS(60)

	// generate a seed for random bomb layout
	seed := c.uint(time.now()._nsec)
	rl.SetRandomSeed(seed)

	// generate a level
	level_map := generate_level()

	when ODIN_DEBUG {
		// run a sanity check on the bomb count
		// TODO: put this behind a DEBUG FLAG
		bcount: int
		for c in level_map {
			if c == 9 {
				bcount += 1
			}
		}
		assert(bcount == MAX_BOMBS, "bomb count does not match MAX_BOMBS")
	}

	// set up initial flag count and a hash to hold the flag indexes
	flag_count := FLAG_COUNT
	flag_hash: [100]int = {}

	// player life and play status for the timer
	alive: bool = true
	game_started: bool = false // for keeping track of whether the player has started the game board
	is_playing: bool = false // for keeping track of whether or not player is paused
	winner: bool = false

	// store the current screen and the previous screen so the pause menu can 
	// resume properly
	prev_screen: SCREEN = .Start
	current_screen: SCREEN = .Start

	// set up the timer
	timer: ^time.Stopwatch = new(time.Stopwatch)
	// time.stopwatch_start(timer)

	// ****
	// GAME LOOP START
	// ****
	for !rl.WindowShouldClose() {
		// find where the player is on the grid 
		player_pos := get_cell_position_from_player_mouse()

		// get the index of the cell that the player is currently moused over
		x_col := (player_pos.x - GRID_BOUND_UPPER_LEFT.x) / c.int(GRID_SIZE)
		y_col := (player_pos.y - GRID_BOUND_UPPER_LEFT.y) / c.int(GRID_SIZE)
		idx := x_col + (y_col * 10) // when this is out of bounds its -21

		hr, min, sec := time.clock_from_stopwatch(timer^)

		// ****
		// HANDLE INPUT EVENTS
		// ****

		switch current_screen {
		case .Start:
			if rl.IsKeyPressed(.ENTER) {
				prev_screen = current_screen
				current_screen = .Game
			} else if rl.IsKeyPressed(.P) {
				prev_screen = current_screen
				current_screen = .Controls
			}
		case .Game:
			if is_playing && game_started {
				time.stopwatch_start(timer)
			}

			if !alive || winner {
				time.stopwatch_stop(timer)
			}

			// handle win condition when all the flags are set
			if flag_count == 0 {
				correct_flags: int
				for flag, i in flag_hash {
					if level_map[i] == 9 && flag_hash[i] > 0 {
						correct_flags += 1
					}
					if correct_flags == FLAG_COUNT {
						break
					}
				}

				winner = correct_flags == FLAG_COUNT
			}

			// p key goes to pause menu with controls explaination
			if rl.IsKeyPressed(.P) {
				is_playing = false // for pausing the timer
				time.stopwatch_stop(timer)
				prev_screen = current_screen
				current_screen = .Controls

				// use the left mouse button to uncover cells
			} else if rl.IsMouseButtonPressed(.LEFT) {
				// propogate_uncover_cell handles uncovering the selected cell and if that cell is not nearby a 
				// bomb, it recursively continues to uncover cells around its neigbors. if the uncovered cell is 
				// a bomb it changes the alive value to false so that the game over can take effect.
				propogate_uncover_cell :: proc(
					lvl: ^[100]int,
					flag_hash: [100]int,
					i: int,
					alive: ^bool,
				) {
					if i >= 0 && i < 100 {
						if lvl[i] > 8 {
							lvl[i] = lvl[i] - 10
							if lvl[i] == -1 {
								alive^ = false
							}
							if lvl[i] == 0 {

								neigbors := get_neigbors(i)
								for n in neigbors {
									if n < 0 || n > 99 { 	// bounds check is important here
										continue
									} else if lvl[n] > 9 {
										// if the index is flagged don't propogate it
										if flag_hash[n] > 0 {
											return
										}
										propogate_uncover_cell(lvl, flag_hash, n, alive)
									}
								}
							}
						}
					}
				}

				// check that the index value is in bounds and the player is not in game over state
				if idx >= 0 && idx < 100 && alive {
					if flag_hash[idx] == 0 {
						if !game_started {
							game_started = true
							is_playing = true
						}
						if !winner && alive {
							propogate_uncover_cell(&level_map, flag_hash, int(idx), &alive)
						}
					}
				}

				// use the right mouse button to set flags
			} else if rl.IsMouseButtonPressed(.RIGHT) {
				if idx >= 0 && idx < 100 && level_map[idx] > 8 && alive && !winner && is_playing {
					// remove the flag from the flags hash and increment the flag count if its already flagged
					if flag_hash[idx] > 0 {
						flag_count += 1
						flag_hash[idx] -= 1
					} else if flag_count > 0 {
						flag_hash[idx] += 1
						flag_count -= 1
					}
				}
				// restart the game if the user presses enter 
			} else if (!alive || winner) && rl.IsKeyPressed(.ENTER) {
				level_map = generate_level()
				flag_hash = {}
				flag_count = FLAG_COUNT
				time.stopwatch_reset(timer)
				alive = true
				winner = false
			}

		case .Controls:
			if rl.IsKeyPressed(.P) {
				current_screen = prev_screen
				if current_screen == .Game {
					if !is_playing {
						is_playing = true
					}
				}
			}
		}

		// ***
		// DRAW STEP
		// ***
		rl.BeginDrawing()
		rl.ClearBackground(rl.BLACK)


		// switch on the current screen to determine what to draw
		switch current_screen {
		case .Start:
			rl.DrawText("Minesweeper", 120, 100, HEADER_FONT_SIZE, rl.WHITE)
			rl.DrawText(
				"press [enter] to start the game, \n\n and [p] to view the controls",
				80,
				220,
				20,
				rl.WHITE,
			)
		case .Game:
			if !alive {
				rl.DrawText("GAME OVER", 180, 20, LABEL_FONT_SIZE, rl.WHITE)
				rl.DrawText("press [enter] to try again", 140, 45, CELL_FONT_SIZE, rl.WHITE)
			}

			if winner {
				rl.DrawText("You Win!", 180, 20, LABEL_FONT_SIZE, rl.WHITE)
				rl.DrawText("press [enter] to try again", 140, 45, CELL_FONT_SIZE, rl.WHITE)
			}

			// DRAW THE TIMER
			mbuf: [4]byte
			sbuf: [4]byte
			hbuf: [4]byte

			padded_hr_str := fmt.bprintf(hbuf[:], "%02d", hr)
			padded_min_str := fmt.bprintf(mbuf[:], "%02d", min)
			padded_sec_str := fmt.bprintf(sbuf[:], "%02d", sec)

			time_str := [3]string{padded_hr_str, padded_min_str, padded_sec_str}

			rl.DrawText(
				strings.clone_to_cstring(strings.join(time_str[:], ":")),
				40,
				65,
				LABEL_FONT_SIZE,
				rl.WHITE,
			)

			// DRAW REMAINING FLAG COUNT LABEL
			draw_flag_icon(FLAG_COUNT_ICON_POSITION)

			flag_icon_label_pos: [2]c.int =  {
				i32(FLAG_COUNT_ICON_POSITION.x) + 30,
				i32(FLAG_COUNT_ICON_POSITION.y),
			}

			buf: [4]byte // buffer for generating the flag count label

			rl.DrawText(
				strings.clone_to_cstring(strconv.itoa(buf[:], flag_count)), // turn the current flag count into a c string
				flag_icon_label_pos.x,
				flag_icon_label_pos.y + 5,
				20,
				rl.WHITE,
			)

			//DRAW GRID 

			// draw bounding box 
			rl.DrawRectangleLines(
				GRID_BOUND_UPPER_LEFT.x,
				GRID_BOUND_UPPER_LEFT.y,
				GRID_RECT_SIZE.x,
				GRID_RECT_SIZE.y,
				rl.WHITE,
			)

			// draw the grid lines
			for i in 1 ..= 10 {
				line_height: c.int = GRID_BOUND_UPPER_LEFT.y + c.int(40 * i)
				line_width: c.int = GRID_BOUND_UPPER_LEFT.x + c.int(40 * i)
				// draw the horizontal lines
				rl.DrawLine(
					GRID_BOUND_UPPER_LEFT.x,
					line_height,
					GRID_RECT_SIZE.x + GRID_BOUND_UPPER_LEFT.x,
					line_height,
					rl.WHITE,
				)
				// draw the vertical lines
				rl.DrawLine(
					line_width,
					GRID_BOUND_UPPER_LEFT.y,
					line_width,
					GRID_RECT_SIZE.y + GRID_BOUND_UPPER_LEFT.y,
					rl.WHITE,
				)
			}

			// DRAW THE LEVEL USING THE LEVEL MAP
			draw_cells(level_map, flag_hash)

			// DRAW THE PLAYER SELECTION SQUARE
			if player_pos != {0, 0} {
				// shift the square down by 1px and slightly shrink so that it fits nicely
				rect := rl.Rectangle{f32(player_pos.x + 1), f32(player_pos.y + 1), 38, 38}
				rl.DrawRectangleRoundedLines(rect, .2, 0, 2, rl.BLUE)
			}
		case .Controls:
			col_1_x: i32 = 50
			col_2_x: i32 = 180
			col_3_x: i32 = 250

			rl.DrawText("Controls", 150, 20, HEADER_FONT_SIZE, rl.WHITE)

			// enter 
			rl.DrawText("[ enter ]", col_1_x, 100, LABEL_FONT_SIZE, rl.WHITE)
			rl.DrawText("starts the game", col_2_x, 100, LABEL_FONT_SIZE, rl.WHITE)

			// pause
			rl.DrawText("[ p ]", col_1_x, 150, LABEL_FONT_SIZE, rl.WHITE)
			rl.DrawText(
				"open the controls menu. \n\npauses the game",
				col_2_x,
				150,
				LABEL_FONT_SIZE,
				rl.WHITE,
			)

			// Game play label
			rl.DrawText("Game Play Controls", 140, 250, LABEL_FONT_SIZE, rl.WHITE)

			rl.DrawText("[ Right Mouse ]", col_1_x, 300, LABEL_FONT_SIZE, rl.WHITE)
			rl.DrawText("set flag on a cell", col_3_x, 300, LABEL_FONT_SIZE, rl.WHITE)

			rl.DrawText("[ Left Mouse ]", col_1_x, 350, LABEL_FONT_SIZE, rl.WHITE)
			rl.DrawText("uncover a cell", col_3_x, 350, LABEL_FONT_SIZE, rl.WHITE)

			rl.DrawText("[ p ] to resume", 160, 470, LABEL_FONT_SIZE, rl.WHITE)
		}

		rl.EndDrawing()
	}
	// ****
	// END GAME LOOP
	// ****
}

// get the top left of the cell the players mouse is on 
get_cell_position_from_player_mouse :: proc() -> (pos: [2]c.int) {
	// find out where the mouse is 
	// remove 10 from the index of the cell
	my := rl.GetMouseY()
	mx := rl.GetMouseX()
	// if the cursor is not within the grid space exit early
	if (my > GRID_RECT_SIZE.y + GRID_BOUND_UPPER_LEFT.y - 5 || my < GRID_BOUND_UPPER_LEFT.y + 5) ||
	   (mx < GRID_BOUND_UPPER_LEFT.x + 5 || mx > GRID_RECT_SIZE.x + GRID_BOUND_UPPER_LEFT.x - 5) {
		return
	}

	// center mouse on the square
	x_center := mx
	y_center := my - 20 // not sure why this offset was needed twice but it is so don't touch it.. 

	// for grid snapping
	offset: [2]c.int = {x_center % 40, y_center % 40 - 20}

	// this is the top corner of the square where the user's mouse is located
	return {x_center - offset.x, y_center - offset.y}
}

// draw_flag_icon is responsible for drawing the flag icon where it is needed. it requires a 
// position for the upper left corner of the flag. 
draw_flag_icon :: proc(start_pos: rl.Vector2) {
	rl.DrawTriangleLines(
		start_pos,
		{start_pos.x + 10, start_pos.y + 5},
		{start_pos.x, start_pos.y + 10},
		rl.WHITE,
	)
	rl.DrawLineV(start_pos, {start_pos.x, start_pos.y + 20}, rl.WHITE)
}

// draws the full map out for debugging
draw_cells :: proc(level: [100]int, flag_hash: [100]int) {
	for cell, idx in level {
		// column and row index of the cell (0 indexed)
		col_idx: c.int = c.int(idx % 10)
		row_idx: c.int = c.int(idx / 10)

		// upper left corner of the cell
		x := GRID_BOUND_UPPER_LEFT.x + (col_idx * c.int(GRID_SIZE))
		y := GRID_BOUND_UPPER_LEFT.y + (row_idx * c.int(GRID_SIZE))

		// offset helps center the text and bombs in the cell
		offset: [2]c.int = {20, 20}

		switch cell {
		// this is an uncovered bomb 
		case -1:
			bomb_offset: c.int = 5
			bomb_size: c.int = 10

			// draw bomb
			rl.DrawRectangle(
				x + offset.x - bomb_offset,
				y + offset.y - bomb_offset,
				bomb_size,
				bomb_size,
				rl.WHITE,
			)

		// this is an uncovered cell which is not near a bomb. nothing to draw here.
		case 0:
			continue

		// these are uncovered cells which are nearby bombs. label the cell with the number 
		// of nearby bombs.
		case 1 ..= 8:
			padding: [2]c.int = {4, 6}
			font_size: c.int = 16
			buf: [4]byte
			// draw the number of nearby bombs
			rl.DrawText(
				strings.clone_to_cstring(strconv.itoa(buf[:], cell)),
				x + offset.x - padding.x,
				y + offset.y - padding.y,
				font_size,
				rl.WHITE,
			)
		// these are all the covered cells
		case:
			// use 1px padding when drawing the squares so the grid can be seen. adjust 
			// the size of the square by 1px on each side as well
			rl.DrawRectangle(x + 1, y + 1, 38, 38, rl.DARKGRAY)
			// draw a flag if the index is flagged
			if flag_hash[idx] > 0 {
				draw_flag_icon({f32(x + 18), f32(y + 10)})
			}

			when ODIN_DEBUG {
				if cell == 9 {
					bomb_offset: c.int = 5
					bomb_size: c.int = 10

					// draw bomb
					rl.DrawRectangle(
						x + offset.x - bomb_offset,
						y + offset.y - bomb_offset,
						bomb_size,
						bomb_size,
						rl.BLUE,
					)
				}
			}
		}
	}
}


// generate_level() generates an array of the values that symbolize the state of each grid cell in 
// the level. whether or not a bomb is in the cell is indicated with a -1 value, and the 
// number of bombs nearby each cell is indicated with values 0-8, 8 being the max. The state
// of the cell as having been uncovered by the player or not, is indicated by adding 10 to 
// the value for uncovered cells. so, a covered bomb would be 9, and upwards of that until 18 
// would be the covered squares coupled with their nearby bomb values. 
// `current_cell_value = cell_actual_value + covered_state, where covered_state = 10 || 0`
generate_level :: proc() -> [100]int {
	level: [100]int

	bhash: [100]int // hash to store rng duplicates and avoid another loop
	for bomb in 0 ..< MAX_BOMBS {
		r_idx := rl.GetRandomValue(0, 99)

		// if we already generated this number then we need to generate another or we'll be short on bombs
		for bhash[r_idx] > 0 {
			r_idx = rl.GetRandomValue(0, 99)
		}

		bhash[r_idx] += 1 // hash accoutning
		level[r_idx] = 9 // covered bomb = 9
	}

	// determine bomb adjacent cells
	for cell, i in level {
		// make sure this cell is not a bomb. 
		if cell == 9 {
			continue
		}

		count: int

		neighbors := get_neigbors(i)

		for n in neighbors {
			if n < 0 || n > 99 {
				continue
			} else {
				if level[n] == 9 {
					count += 1
				}
			}
		}

		// select that as the num value of the cell
		level[i] = count + 10
	}

	return level
}

// get neighbors gets all the indexes of neigboring cells given an index of a cell. 
// any neigboring cell that is out of bounds will be negative
get_neigbors :: proc(i: int) -> (neighbors: [9]int) {
	top_edge := i < GRID_WIDTH
	left_edge := i % GRID_WIDTH == 0
	right_edge := (i + 1) % GRID_WIDTH == 0
	bottom_edge := i > 90

	neighbors = {i - 11, i - 10, i - 9, i - 1, i, i + 1, i + 9, i + 10, i + 11}

	// set the edges that shouldn't be calcluated out of bounds
	if top_edge {
		neighbors[0] = -1
		neighbors[1] = -1
		neighbors[2] = -1
	}
	if bottom_edge {
		neighbors[6] = -1
		neighbors[7] = -1
		neighbors[8] = -1
	}
	if right_edge {
		neighbors[2] = -1
		neighbors[5] = -1
		neighbors[8] = -1
	}
	if left_edge {
		neighbors[0] = -1
		neighbors[3] = -1
		neighbors[6] = -1
	}

	return neighbors
}
