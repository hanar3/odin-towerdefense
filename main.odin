package main
import "core:fmt"
import "core:log"
import "core:math/linalg"
import "core:strconv"
import "core:strings"
import "core:time"
import rl "vendor:raylib"

WINDOW_WIDTH :: 800
WINDOW_HEIGHT :: 800

GameState :: enum {
	PLAYING,
	INTERVAL,
}

Global :: struct {
	score:         uint,
	money:         uint,
	wave:          uint,
	wave_start:    time.Time,
	wave_duration: time.Duration,
	state:         GameState,
}
global := Global {
	wave_duration = time.Second * 10,
	wave_start    = time.now(),
	wave          = 1,
	state         = GameState.PLAYING,
}

Player :: struct {
	hp:              int,
	center:          rl.Vector2,
	rect:            rl.Rectangle,
	range:           f32,
	fire_rate:       int,
	last_shoot_time: time.Time,
}

Enemy :: struct {
	id:                 int,
	center:             rl.Vector2,
	rect:               rl.Rectangle,
	direction:          rl.Vector2,
	speed:              f32,
	hp:                 int,
	projected_hp:       int,
	distance_to_player: f32,
	dead:               bool,
}

Projectile :: struct {
	id:        int,
	atk:       int,
	speed:     f32,
	radius:    f32,
	direction: rl.Vector2,
	position:  rl.Vector2,
	target:    ^Enemy,
	dead:      bool,
}

spawn_enemy :: proc(enemies: ^[dynamic]^Enemy, player: ^Player, id: ^int) {
	log.debug("creating enemies")
	if len(enemies) < 1000 {
		create_dir := linalg.normalize(
			rl.Vector2 {
				cast(f32)rl.GetRandomValue(-100, 100),
				cast(f32)rl.GetRandomValue(-100, 100),
			},
		)
		enemy_center :=
			rl.Vector2{WINDOW_WIDTH / 2, WINDOW_HEIGHT / 2} +
			rl.Vector2{WINDOW_WIDTH * 1, WINDOW_HEIGHT * 1} * create_dir

		hp := 100
		enemy := new(Enemy)
		enemy.id = id^
		enemy.hp = hp
		enemy.projected_hp = hp
		enemy.speed = 150.0
		enemy.center = enemy_center
		enemy.rect = {enemy_center.x - 5, enemy_center.y - 5, 10, 10}
		enemy.direction = linalg.normalize(player.center - enemy_center)
		enemy.distance_to_player = linalg.vector_length2(player.center - enemy_center)
		enemy.dead = false
		append(enemies, enemy)
		id^ += 1
	}
}

spawn_projectile :: proc(
	player: ^Player,
	enemy: ^Enemy,
	projectiles: ^[dynamic]^Projectile,
	id: ^int,
) {
	log.debug("checking closer enemy")
	if enemy != nil && enemy.distance_to_player < (player.range * player.range) {
		duration := time.since(player.last_shoot_time)
		if time.duration_milliseconds(duration) >= 1000.0 / f64(player.fire_rate) {
			player.last_shoot_time = time.now()
			atk := 50
			projectile := new(Projectile)
			projectile.id = id^
			projectile.atk = atk
			projectile.speed = 500.0
			projectile.radius = 5
			projectile.position = player.center
			projectile.direction = linalg.normalize(enemy.center - player.center)
			projectile.target = enemy
			projectile.dead = false
			append(projectiles, projectile)
			id^ += 1
			enemy.projected_hp -= atk
		}
	}
}

process_enemies :: proc(enemies: ^[dynamic]^Enemy, player: ^Player, frame_time: f32) -> ^Enemy {
	log.debug("processing enemies")
	closest_enemy: ^Enemy = nil
	for enemy in enemies {
		// rl.DrawRectangleRec(enemy.rect, rl.BLUE)
		collided := rl.CheckCollisionRecs(enemy.rect, player.rect)
		enemy.distance_to_player = linalg.vector_length2(player.center - enemy.center)

		if closest_enemy == nil || closest_enemy.distance_to_player > enemy.distance_to_player {
			if enemy.projected_hp > 0 {
				closest_enemy = enemy
			}
		}

		if collided {
			// enemy.dead = true
			// dead_enemies += 1
		} else {
			move := enemy.direction * enemy.speed * frame_time
			enemy.center += move
			enemy.rect.x += move.x
			enemy.rect.y += move.y
		}
	}

	return closest_enemy
}

draw_enemies :: proc(enemies: ^[dynamic]^Enemy) {
	for enemy in enemies {
		rl.DrawRectangleRec(enemy.rect, rl.BLUE)
	}
}

/* compute damage, enemy hp/projected hp and removes enemy from list if hp reaches 0 */
projectile_hit :: proc(projectile: ^Projectile) {
	damage := projectile.atk
	projectile.target.hp -= damage
	projectile.target.projected_hp -= (damage - projectile.atk) // if we add a possible crit, we need to further reduce the projected hp by the difference
}

is_outbound_circle :: proc(position: rl.Vector2, radius: f32) -> bool {
	return(
		position.x >= (WINDOW_WIDTH + radius) ||
		position.x < 0 ||
		position.y < 0 ||
		position.y >= (WINDOW_HEIGHT + radius) \
	)
}

process_projectiles :: proc(
	projectiles: ^[dynamic]^Projectile,
	dead_enemies: ^int,
	dead_projectiles: ^int,
	frame_time: f32,
) {
	log.debug("processing projectiles")
	for projectile, index in projectiles {
		if projectile.target.dead {
			continue
		}
		if rl.CheckCollisionCircleRec(
			projectile.position,
			projectile.radius,
			projectile.target.rect,
		) {
			projectile_hit(projectile)
			if projectile.target.hp <= 0 {
				projectile.target.dead = true
				dead_enemies^ += 1
				global.score += 10
				global.money += 1
			} else {
				projectile.dead = true
				dead_projectiles^ += 1
			}
		} else if is_outbound_circle(projectile.position, projectile.radius) {
			projectile.dead = true
			dead_projectiles^ += 1
		}

		projectile.position += projectile.direction * projectile.speed * frame_time
	}
}

draw_projectiles :: proc(projectiles: ^[dynamic]^Projectile) {
	for projectile in projectiles {
		rl.DrawCircleV(projectile.position, projectile.radius, rl.RED)
	}
}

clean_projectiles :: proc(projectiles: ^[dynamic]^Projectile) {
	log.debug("removing projectiles")
	for i := 0; i < len(projectiles); {
		projectile := projectiles[i]
		if projectile.dead || projectile.target.dead {
			free(projectiles[i])
			unordered_remove(projectiles, i)
		} else {
			i += 1
		}
	}
}

clean_enemies :: proc(enemies: ^[dynamic]^Enemy) {
	log.debug("removing enemies")
	for i := 0; i < len(enemies); {
		if enemies[i].dead {
			free(enemies[i])
			unordered_remove(enemies, i)
		} else {
			i += 1
		}
	}
}

main :: proc() {
	using rl
	context.logger = log.create_console_logger(.Info)

	SetConfigFlags({ConfigFlag.MSAA_4X_HINT})
	InitWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "towercopy")
	defer CloseWindow()
	SetTargetFPS(60)

	player_center := Vector2{f32(WINDOW_WIDTH / 2), f32(WINDOW_HEIGHT / 2)}
	player := Player {
		hp              = 100,
		range           = 200,
		fire_rate       = 2,
		center          = player_center,
		rect            = {player_center.x - 40 / 2, player_center.y - 80 / 2, 40, 80},
		last_shoot_time = time.now(),
	}

	enemies := [dynamic]^Enemy{}
	projectiles := [dynamic]^Projectile{}

	it := 0
	dead_enemies := 0
	dead_projectiles := 0

	projectile_id := 0
	enemy_id := 0
	frame_time: f32
	closest_enemy: ^Enemy
	state_changed_time := global.wave_start

	enemies_per_wave := 10 + uint(f32(global.wave) / 2.0)
	enemy_spawn_time := time.now()
	enemy_spawn_count: uint = 0
	enemy_spawn_delay := global.wave_duration / time.Duration(enemies_per_wave)

	for !WindowShouldClose() {
		frame_time = GetFrameTime()
		BeginDrawing()
		defer EndDrawing()

		before := time.now()

		if global.state == GameState.PLAYING {
			if enemy_spawn_count < enemies_per_wave &&
			   time.since(enemy_spawn_time) > enemy_spawn_delay {
				spawn_enemy(&enemies, &player, &enemy_id)
				enemy_spawn_time = time.now()
				enemy_spawn_count += 1
			}

			if time.since(state_changed_time) > global.wave_duration {
				global.state = GameState.INTERVAL
				state_changed_time = time.now()
			}
			DrawText("PLAYING", WINDOW_WIDTH - 100, 10, 14, BLACK)
		} else if (global.state == GameState.INTERVAL) {
			if time.since(state_changed_time) > time.Second * 5 {
				global.state = GameState.PLAYING
				state_changed_time = time.now()
				global.wave += 1
				enemy_spawn_count = 0
			}
			DrawText("INTERVAL", WINDOW_WIDTH - 100, 10, 14, BLACK)
		}

		buf: [4]byte = {}


		wave_text := strings.concatenate({"wave: ", strconv.itoa(buf[:], cast(int)global.wave)})
		defer delete(wave_text)
		wave_text_cstring := strings.clone_to_cstring(wave_text)
		defer delete(wave_text_cstring)
		DrawText(wave_text_cstring, WINDOW_WIDTH - 100, 30, 14, BLACK)

		score_text := strings.concatenate({"score: ", strconv.itoa(buf[:], cast(int)global.score)})
		defer delete(score_text)
		score_text_cstring := strings.clone_to_cstring(score_text)
		defer delete(score_text_cstring)
		DrawText(score_text_cstring, WINDOW_WIDTH - 100, 50, 14, BLACK)

		money_text := strings.concatenate({"money: ", strconv.itoa(buf[:], cast(int)global.money)})
		defer delete(money_text)
		money_text_cstring := strings.clone_to_cstring(money_text)
		defer delete(money_text_cstring)
		DrawText(money_text_cstring, WINDOW_WIDTH - 100, 70, 14, BLACK)

		closest_enemy = process_enemies(&enemies, &player, frame_time)
		// fmt.println("process_enemies", time.since(before))

		before = time.now()
		spawn_projectile(&player, closest_enemy, &projectiles, &projectile_id)
		// fmt.println("spawn_projectile", time.since(before))

		before = time.now()
		process_projectiles(&projectiles, &dead_enemies, &dead_projectiles, frame_time)
		// fmt.println("process_projectiles", time.since(before))

		if dead_projectiles > 0 || dead_enemies > 0 {
			before = time.now()
			clean_projectiles(&projectiles)
			// fmt.println("clean_projectiles", time.since(before))
		}

		if dead_enemies > 0 {
			before = time.now()
			clean_enemies(&enemies)
			// fmt.println("clean_enemies", time.since(before))
		}

		dead_projectiles = 0
		dead_enemies = 0

		ClearBackground(DARKBLUE)
		DrawRectangleRec(player.rect, RED)
		DrawCircleLinesV(player_center, player.range, GREEN)
		draw_enemies(&enemies)
		draw_projectiles(&projectiles)
		DrawFPS(10, 10)

		it += 1
	}
}
