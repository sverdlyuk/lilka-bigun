-- Бігун — приклад для журналу: спрайти, анімація, фон, вороги, звук.
-- Керування: A / вгору — стрибок; вниз — пригнутися; B — вихід.
-- Наземних (равлик, черв'як, жабка) — ПЕРЕСТРИБУЙ. Бджолу зверху — ПРИГНИСЬ.
-- Гра поступово пришвидшується. Усі ресурси — у теці resources/ поряд.

local W, H
local FEET = 155          -- лінія землі (де стоять ноги)
local HX = 26             -- герой завжди на цьому X
local hero = {}           -- y, vy, onGround, ducking
local things = {}         -- вороги на екрані: {def, x, phase}
local time, spawnT, speed, score, state
local bg, run1, run2, jump, duck, sndJump, sndHurt
local SW, SH, DW, DH, INK, bgW, bgx
local EN                  -- описи ворогів (тип, кадри, «доріжка»)

local function reset()
  hero.y, hero.vy, hero.onGround, hero.ducking = 0, 0, true, false
  things = {}
  bgx = 0
  time, spawnT, speed, score, state = 0, 1.6, 80, 0, "play"
end

local function img(n) return resources.load_image("resources/" .. n .. ".png", display.color565(255, 0, 255)) end

function lilka.init()
  W, H = display.width, display.height
  bg    = resources.load_image("resources/bg.png")
  bgW   = bg.width
  run1, run2, jump, duck = img("run1"), img("run2"), img("jump"), img("duck")
  sndJump = resources.load_audio("resources/jump.wav")
  sndHurt = resources.load_audio("resources/hurt.wav")
  audio.set_volume(0.6)
  SW, SH = run1.width, run1.height
  DW, DH = duck.width, duck.height
  INK = display.color565(30, 30, 32)
  -- lane="ground" — перестрибуй; lane="air" — пригинайся; hop — жабка підскакує
  EN = {
    { name = "snail", a = img("snail_a"), b = img("snail_b"), lane = "ground" },
    { name = "worm",  a = img("worm_a"),  b = img("worm_b"),  lane = "ground" },
    { name = "frog",  a = img("frog_a"),  b = img("frog_b"),  lane = "ground", hop = true },
    { name = "bee",   a = img("bee_a"),   b = img("bee_b"),   lane = "air" },
  }
  reset()
end

-- поточний верхній Y ворога (враховує стрибки жабки й гойдання бджоли)
local function thingY(t)
  local d = t.def
  if d.lane == "air" then
    return (FEET - 28) - d.a.height + math.sin(time * 4 + t.phase) * 3
  end
  local top = FEET - d.a.height
  if d.hop then top = top - math.abs(math.sin(time * 5 + t.phase)) * 14 end
  return top
end

-- який кадр показати
local function thingSpr(t)
  local d = t.def
  if d.hop then
    return (math.abs(math.sin(time * 5 + t.phase)) > 0.3) and d.b or d.a
  end
  return (math.floor(time / 0.12) % 2 == 0) and d.a or d.b
end

local function spawn()
  -- УВАГА: на Лілці math.random(n) дає 0..n-1 (стиль Arduino), тому +1 -> 1..#EN
  local idx = math.random(#EN) + 1
  things[#things + 1] = { def = EN[idx], x = W + 10, phase = math.random() * 6.28 }
end

function lilka.update(delta)
  local s = controller.get_state()
  if s.b.just_pressed then util.exit() end            -- вихід

  -- пауза на START: перемикаємо play <-> pause
  if s.start.just_pressed and state ~= "over" then
    state = (state == "pause") and "play" or "pause"
  end
  if state == "pause" then return end                 -- застигли: нічого не рухаємо

  if state == "over" then
    if s.a.just_pressed then reset() end
    return
  end

  time = time + delta
  speed = 80 + time * 3                               -- плавно швидше (спокійний старт)
  if speed > 240 then speed = 240 end

  -- прокрутка фону: повільніше за ворогів (паралакс = відчуття глибини)
  bgx = bgx - speed * 0.4 * delta
  if bgx <= -bgW then bgx = bgx + bgW end

  -- пригнутися / стрибнути (на землі)
  hero.ducking = hero.onGround and s.down.pressed
  if hero.onGround and not hero.ducking and (s.a.just_pressed or s.up.just_pressed) then
    hero.vy, hero.onGround = -330, false
    audio.play(sndJump)
  end
  hero.vy = hero.vy + 850 * delta
  hero.y = hero.y + hero.vy * delta
  if hero.y >= 0 then hero.y, hero.vy, hero.onGround = 0, 0, true end

  -- поява ворогів (частіше з часом)
  spawnT = spawnT - delta
  if spawnT <= 0 then
    local base = 1.4 - time * 0.012
    if base < 0.65 then base = 0.65 end
    spawnT = base + math.random() * 0.5
    spawn()
  end

  -- прямокутник героя (нижчий, коли пригнувся)
  local hy, hh, hw = FEET - SH + hero.y, SH, SW
  if hero.ducking then hy, hh, hw = FEET - DH, DH, DW end

  local i = 1
  while i <= #things do
    local t = things[i]
    t.x = t.x - speed * delta
    local w, h, ty = t.def.a.width, t.def.a.height, thingY(t)
    -- перекриття прямокутників (трохи звужене — прощає легкий дотик)
    if t.x + w - 4 > HX + 4 and t.x + 4 < HX + hw - 4 and ty + h - 3 > hy + 3 and ty + 3 < hy + hh - 3 then
      state = "over"; audio.play(sndHurt)
    end
    if t.x < -w then table.remove(things, i); score = score + 1
    else i = i + 1 end
  end
end

function lilka.draw()
  -- фон малюємо двічі поруч і зсуваємо — виходить нескінченна прокрутка
  local bx = math.floor(bgx)
  display.draw_image(bg, bx, 0)
  display.draw_image(bg, bx + bgW, 0)

  for _, t in ipairs(things) do
    display.draw_image(thingSpr(t), math.floor(t.x), math.floor(thingY(t)))
  end

  -- герой: у повітрі — jump; пригнувся — duck; на землі — біг run1/run2
  if not hero.onGround then
    display.draw_image(jump, HX, math.floor(FEET - SH + hero.y))
  elseif hero.ducking then
    display.draw_image(duck, HX, FEET - DH)
  else
    display.draw_image((math.floor(time / 0.12) % 2 == 0) and run1 or run2, HX, FEET - SH)
  end

  display.set_text_color(INK)
  display.set_text_size(1)
  display.set_cursor(math.floor(W / 2 - 34), 18)      -- рахунок по центру, нижче кутів
  display.print("Рахунок: " .. score)

  if state == "pause" then
    display.set_text_size(2)
    display.set_cursor(math.floor(W / 2 - 40), math.floor(H / 2 - 8))
    display.print("ПАУЗА")
  end

  if state == "over" then
    display.set_text_size(2)
    display.set_cursor(math.floor(W / 2 - 46), math.floor(H / 2 - 10))
    display.print("КІНЕЦЬ")
    display.set_text_size(1)
    display.set_cursor(math.floor(W / 2 - 52), math.floor(H / 2 + 14))
    display.print("A - ще раз")
  end
end
