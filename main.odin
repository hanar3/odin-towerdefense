package main
import "core:fmt"
import "core:math/big"
import "core:math/linalg"
import "core:strconv"
import "core:strings"
import "core:time"
import rl "vendor:raylib"

WINDOW_WIDTH :: 800
WINDOW_HEIGHT :: 800

Player :: struct {
	hp:              int,
	rect:            rl.Rectangle,
	range:           f32,
	fire_rate:       int,
	last_shoot_time: time.Time,
}

Enemy :: struct {
	id:                 int,
	rect:               rl.Rectangle,
	direction:          rl.Vector2,
	speed:              f32,
	hp:                 int,
	distance_to_player: f32,
}

Projectile :: struct {
	atk:       int,
	speed:     f32,
	radius:    f32,
	direction: rl.Vector2,
	position:  rl.Vector2,
}

check_projectiles_to_enemy :: proc(
	enemy: ^Enemy,
	projectiles: ^[dynamic]Projectile,
) -> (
	^Projectile,
	int,
) {
	for &projectile, index in projectiles {
		collided := rl.CheckCollisionCircleRec(projectile.position, projectile.radius, enemy.rect)
		if collided {
			return &projectile, index
		}
	}

	return nil, 0
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

main :: proc() {
	using rl

	SetConfigFlags({ConfigFlag.MSAA_4X_HINT})
	InitWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "towercopy")
	defer CloseWindow()
	SetTargetFPS(1200)

	player_center := Vector2{f32(WINDOW_WIDTH / 2), f32(WINDOW_HEIGHT / 2)}
	player := Player {
		hp              = 100,
		range           = 200,
		fire_rate       = 1000,
		rect            = {player_center.x - 40 / 2, player_center.y - 80 / 2, 40, 80},
		last_shoot_time = time.now(),
	}

	enemies := [dynamic]Enemy{}
	projectiles := [dynamic]Projectile{}

	for !WindowShouldClose() {
		frame_time := GetFrameTime()
		BeginDrawing()
		defer EndDrawing()

		ClearBackground(DARKBLUE)
		DrawRectangleRec(player.rect, RED)
		DrawCircleLinesV(player_center, player.range, GREEN)

		create_dir := Vector2 {
			cast(f32)GetRandomValue(-100, 100),
			cast(f32)GetRandomValue(-100, 100),
		}


		enemy_center :=
			Vector2{WINDOW_WIDTH / 2, WINDOW_HEIGHT / 2} +
			Vector2{WINDOW_WIDTH * 1, WINDOW_HEIGHT * 1} * linalg.normalize(create_dir)

		dir := player_center - enemy_center

		if len(&enemies) < 100 {
			append(
				&enemies,
				Enemy {
					id = cast(int)GetRandomValue(0, 1000),
					hp = 100,
					speed = 150.0,
					rect = {enemy_center.x - 5, enemy_center.y - 5, 10, 10},
					direction = linalg.normalize(dir),
					distance_to_player = linalg.vector_length2(player_center - enemy_center),
				},
			)
		}


		enemies_to_remove := [dynamic]int{}
		closer_enemy: ^Enemy = nil
		for &enemy, index in enemies {
			DrawRectangleRec(enemy.rect, BLUE)
			collided := CheckCollisionRecs(enemy.rect, player.rect)
			enemy_center: Vector2 = {
				enemy.rect.x + enemy.rect.width / 2,
				enemy.rect.y + enemy.rect.height / 2,
			}
			distance := linalg.vector_length2(player_center - enemy_center)
			enemy.distance_to_player = distance

			if closer_enemy == nil || closer_enemy.distance_to_player > distance {
				closer_enemy = &enemy
			}


			projectile, pindex := check_projectiles_to_enemy(&enemy, &projectiles)

			if projectile != nil {
				unordered_remove(&projectiles, pindex)
				enemy.hp -= projectile.atk
				if enemy.hp <= 0 {
					append(&enemies_to_remove, index)
				}
			}

			if collided {
				append(&enemies_to_remove, index)
			} else {
				enemy.rect.x += enemy.direction.x * enemy.speed * frame_time
				enemy.rect.y += enemy.direction.y * enemy.speed * frame_time
			}
		}

		// Projectile processing
		projectiles_to_remove := [dynamic]int{}
		for &projectile, index in projectiles {
			enemy, enemy_index := check_enemies_to_projectile(&projectile, &enemies)
			if enemy != nil {
				enemy.hp -= projectile.atk
				if enemy.hp <= 0 {
					unordered_remove(&enemies, enemy_index)
				}
				append(&projectiles_to_remove, index)
			} else {

				if projectile.position.x >= WINDOW_WIDTH ||
				   projectile.position.x < 0 ||
				   projectile.position.y < 0 ||
				   projectile.position.y >= WINDOW_HEIGHT {
					append(&projectiles_to_remove, index)
				}
			}

			projectile.position += projectile.direction * projectile.speed * frame_time
			DrawCircleV(projectile.position, projectile.radius, RED)
		}

		if closer_enemy.distance_to_player < (player.range * player.range) {
			closer_enemy_center: Vector2 = {
				closer_enemy.rect.x + closer_enemy.rect.width / 2,
				closer_enemy.rect.y + closer_enemy.rect.height / 2,
			}

			duration := time.since(player.last_shoot_time)
			ms_elapsed := time.duration_milliseconds(duration)
			if ms_elapsed >= cast(f64)(1000 / player.fire_rate) {
				player.last_shoot_time = time.now()
				append(
					&projectiles,
					Projectile {
						atk = 50,
						speed = 500.0,
						radius = 5,
						position = player_center,
						direction = linalg.normalize(closer_enemy_center - player_center),
					},
				)
			}


		}


		for projectile_idx, index in projectiles_to_remove {
			ordered_remove(&projectiles, projectile_idx - index)
		}


		for enemy_idx, index in enemies_to_remove {
			ordered_remove(&enemies, enemy_idx - index)
		}

		DrawFPS(10, 10)

	}
}
