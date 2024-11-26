package main
import "core:fmt"
import "core:math/linalg"
import "core:sort"
import "core:strconv"
import "core:strings"
import "core:time"
import rl "vendor:raylib"

WINDOW_WIDTH :: 800
WINDOW_HEIGHT :: 800

Player :: struct {
	hp:              int,
	center:          rl.Vector2,
	rect:            rl.Rectangle,
	range:           f32,
	fire_rate:       f64,
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
}

Projectile :: struct {
	atk:       int,
	speed:     f32,
	radius:    f32,
	direction: rl.Vector2,
	position:  rl.Vector2,
}

check_enemies_to_projectile :: proc(
	projectile: ^Projectile,
	enemies: ^[dynamic]Enemy,
) -> (
	^Enemy,
	int,
) {
	for &enemy, index in enemies {
		collided := rl.CheckCollisionCircleRec(projectile.position, projectile.radius, enemy.rect)
		if collided {
			return &enemy, index
		}
	}

	return nil, 0
}

/* compute damage, enemy hp/projected hp and removes enemy from list if hp reaches 0 */
projectile_hit :: proc(projectile: ^Projectile, enemy: ^Enemy) {
	damage := projectile.atk
	enemy.hp -= damage
	enemy.projected_hp -= (damage - projectile.atk) // if we add a possible crit, we need to further reduce the projected hp by the difference
}

main :: proc() {
	using rl

	SetConfigFlags({ConfigFlag.MSAA_4X_HINT})
	InitWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "towercopy")
	defer CloseWindow()
	SetTargetFPS(12000)

	player_center := Vector2{f32(WINDOW_WIDTH / 2), f32(WINDOW_HEIGHT / 2)}
	player := Player {
		hp              = 100,
		range           = 200,
		fire_rate       = 1500,
		center          = player_center,
		rect            = {player_center.x - 40 / 2, player_center.y - 80 / 2, 40, 80},
		last_shoot_time = time.now(),
	}

	enemies := [dynamic]Enemy{}
	projectiles := [dynamic]Projectile{}

	enemies_to_remove := [dynamic]int{}
	projectiles_to_remove := [dynamic]int{}

	for !WindowShouldClose() {
		frame_time := GetFrameTime()
		BeginDrawing()
		defer EndDrawing()

		ClearBackground(DARKBLUE)
		DrawRectangleRec(player.rect, RED)
		DrawCircleLinesV(player_center, player.range, GREEN)


		if len(&enemies) < 1000 {
			create_dir := Vector2 {
				cast(f32)GetRandomValue(-100, 100),
				cast(f32)GetRandomValue(-100, 100),
			}
			enemy_center :=
				Vector2{WINDOW_WIDTH / 2, WINDOW_HEIGHT / 2} +
				Vector2{WINDOW_WIDTH * 1, WINDOW_HEIGHT * 1} * linalg.normalize(create_dir)

			hp := 100
			append(
				&enemies,
				Enemy {
					id = cast(int)GetRandomValue(0, 1000),
					hp = hp,
					projected_hp = hp,
					speed = 150.0,
					center = enemy_center,
					rect = {enemy_center.x - 5, enemy_center.y - 5, 10, 10},
					direction = linalg.normalize(player.center - enemy_center),
					distance_to_player = linalg.vector_length2(player.center - enemy_center),
				},
			)
		}

		closer_enemy: ^Enemy = nil
		for &enemy, index in enemies {
			DrawRectangleRec(enemy.rect, BLUE)
			collided := CheckCollisionRecs(enemy.rect, player.rect)
			distance := linalg.vector_length2(player_center - enemy.center)
			enemy.distance_to_player = distance

			if closer_enemy == nil || closer_enemy.distance_to_player > distance {
				if enemy.projected_hp > 0 {
					closer_enemy = &enemy
				}
			}

			if collided {
				append(&enemies_to_remove, index)
			} else {
				move := enemy.direction * enemy.speed * frame_time
				enemy.center += move
				enemy.rect.x += move.x
				enemy.rect.y += move.y
			}
		}

		// Projectile processing
		for &projectile, index in projectiles {
			enemy, enemy_index := check_enemies_to_projectile(&projectile, &enemies)
			if enemy != nil {
				projectile_hit(&projectile, enemy) // why is this not working?
				if enemy.hp <= 0 {
					unordered_remove(&enemies, enemy_index)
				}
				append(&projectiles_to_remove, index)
			} else if projectile.position.x >= (WINDOW_WIDTH + projectile.radius) ||
			   projectile.position.x < 0 ||
			   projectile.position.y < 0 ||
			   projectile.position.y >= (WINDOW_HEIGHT + projectile.radius) {
				append(&projectiles_to_remove, index)
			}

			projectile.position += projectile.direction * projectile.speed * frame_time
			DrawCircleV(projectile.position, projectile.radius, RED)
		}

		if closer_enemy.distance_to_player < (player.range * player.range) {
			duration := time.since(player.last_shoot_time)
			ms_elapsed := time.duration_milliseconds(duration)
			if ms_elapsed >= 1000.0 / player.fire_rate {
				player.last_shoot_time = time.now()
				atk := 50
				append(
					&projectiles,
					Projectile {
						atk = atk,
						speed = 500.0,
						radius = 5,
						position = player.center,
						direction = linalg.normalize(closer_enemy.center - player.center),
					},
				)
				closer_enemy.projected_hp -= atk
			}
		}

		for projectile_idx, index in projectiles_to_remove {
			ordered_remove(&projectiles, projectile_idx - index)
		}

		for enemy_idx, index in enemies_to_remove {
			ordered_remove(&enemies, enemy_idx - index)
		}

		clear(&projectiles_to_remove)
		clear(&enemies_to_remove)

		DrawFPS(10, 10)

	}
}
