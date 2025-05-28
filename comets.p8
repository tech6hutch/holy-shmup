pico-8 cartridge // http://www.pico-8.com
version 42
__lua__
--numbers only have 16 bits for the integer part, but shifting the value right
--by 16 lets us also use the remaining bits, intended for the decimal part. This
--gives us a total of 32 bits for storing our (signed) integer.
SCORE_SHIFT=16

function _init()
	--reset log
	printh("-- start --","log.txt",true)
	--disable btnp repeat
	poke(0x5f5c,255)
	--disable print() autoscroll
	poke(0x5f36,0x40)

	enemies_setup()

	--skip intro
	t=0 init_game() do return end

	_update,_draw=intro
	t,entities,stars,star_spawn_y,star_speed_scale,kolob=0,{},{},-300-64,1
	generate_stars()
	jc=add_entity{
		x=64,y=64,
		spr=16,
	}
	for i=1,3 do
		add_entity{
			x=rnd(64)+32, y=rnd(16)+94,
			spr=17,
		}
	end
end

function intro()
	t+=1
	camera(0,jc.y-65)
	if t>380 then
		jc.spr=t\2%3+1
		jc.y-=2
		if jc.y<-300 then
			camera()
			init_game()
			return
		end
	elseif t>320 then
		jc.y-=lerp(0,2,(t-320)/380)
	end

	cls(0)
	local background={
		{-201,-193, 0|(1<<4), 0b0011111111001111},
		{-192,-71, 1},
		{-71,-64, 1|(12<<4), 0b0011111111001111},
		{-63,59, 12},
		{60,127, 3},
		{61,127, 3|(11<<4), 0b1011111111101111},
	}
	for bg in all(background) do
		local y1,y2,c,f=unpack(bg)
		fillp(f)
		rectfill(0,y1,127,y2,c)
	end
	fillp()
	draw_stars(true)
	foreach(entities,_draw_ent)
	if t>=320 then
	elseif t>=210 then
		print("jesus:", 16,0, 0)
		print("you can't follow me now,\nbut someday.")
	elseif t>=120 then
		print("peter:", 26,40, 0)
		print("we will follow you.")
	elseif t>=30 then
		print("jesus:", 16,0, 0)
		print("i go to him who sent me.")
	end
end

function init_game()
	_update,_draw,score,level=update_game,draw_game,0,7
	local star_spawn_offset=0-(star_spawn_y or 0)
	star_spawn_y=0
	if stars then
		for star in all(stars) do
			star.y+=star_spawn_offset
		end
	else
		stars={}
		generate_stars()
	end
	entities,explosions,popups={},{},{}
	jc=add_entity{
		x=64,y=64,
		preserve_offscreen=true,
	}
	init_next_level()
end

function init_next_level()
	level+=1
	star_speed_scale=1
	level_warp_t,level_soft_end_t,entity_spawn_t,no_shoot_until_t=0,t+30*5,t+90,0
end

--need to define ENEMIES global in a function because we need a util function,
--which won't exist until _init() since lua doesn't hoist.
--the "__kind" fields are just for debugging, and may be removed if needed.
function enemies_setup()
	local function asteroid_update(self)
		self.y+=1
		self.flip_x,self.flip_y, self.spr=
			rnd{false,true},rnd{false,true},
			rnd{32,33}
	end
	local DEMON_PROTOTYPE={
		__kind="red demon",
		hp=5,
		score=2,
		timer=15, speed=1,
		init=function(self)
			self.target=self:get_new_target()
		end,
		update=function(self)
			if self.target then
				self.spr=34
				move_ent_toward_ent(self,self.target,self.speed)
				self.timer-=1
				if self.timer<=0 then
					if(self.shoot)self:shoot()
					self.timer,self.target=15*self.speed
				end
			else
				self.spr=35
				self.timer-=1
				if self.timer<=0 then
					self.timer,self.target=15,self:get_new_target()
				end
			end
		end,
		get_new_target=function()
			return copy(jc)
		end,
	}
	local DEMON_SHOOTS_PROTOTYPE={
		__kind="red demon (shoots)",
		hp=5,
		score=3,
		speed=1.5,
		update=function(self)
			if self.timer then
				self.spr=35
				self.y+=1
				self.timer-=1
				if self.timer<=0 then
					self.timer=nil
				end
			else
				self.spr=34
				self.y+=self.speed
				if self:shoot() then
					self.timer=15*self.speed
				end
			end
		end,
		shoot=function(self)
			if abs(self.y-jc.y)<16 then
				for x in all{-1,1} do
					shoot(self.x,self.y, {x,0.5})
				end
				return true
			end
		end,
	}
	local DEMON_BLUE_PARTS={
		hp=3,
		pal={[8]=12,[2]=10},
		speed=2,
	}

	ENEMIES={
		{ --asteroid 1 (comes straight down)
			hp=3,
			update=asteroid_update,
		},
		{ --asteroid 2 (sways)
			hp=3,
			score=2,
			init=function(self)
				self.start_x,self.start_time,self.period,self.distance=self.x,time(),rnd(1),rnd(20)
			end,
			update=function(self)
				asteroid_update(self)
				self.x=self.start_x+sin((time()-self.start_time)*self.period)*self.distance
			end,
		},
		DEMON_PROTOTYPE, --red demon
		copy(DEMON_PROTOTYPE,DEMON_BLUE_PARTS,{ --blue demon
			__kind="blue demon",
		}),
		{ --ufo
			spr=36, pal={},
			score=3,
			time_until_shoot=60,
			update=function(self)
				self.y+=1
				self.time_until_shoot-=1
				if self.time_until_shoot<=0 then
					self.pal[1]=1
					self.time_until_shoot=60
					shoot(self.x,self.y,direction_from_ent_to_ent(self,jc))
				elseif self.time_until_shoot<15 then
					self.pal[1]=7
				end
			end,
		},
		DEMON_SHOOTS_PROTOTYPE, --red demon (shoots)
		copy(DEMON_SHOOTS_PROTOTYPE,DEMON_BLUE_PARTS,{ --blue demon (shoots)
			__kind="blue demon (shoots)",
			shoot=function(self)
				local y_dif=jc.y-self.y
				if
					y_dif>-8 and y_dif<64
					or y_dif<0 and abs(self.x-jc.x)<16
				then
					for x in all{-1,1} do
						shoot(self.x,self.y, {x,1})
					end
					shoot(self.x,self.y, {0,-1})
					return true
				end
			end,
		}),
	}
end

--per level.
ENEMY_PROBABILITIES={
	--asteroid, +swaying, red, blue, ufo, red(shoot), blue(shoot).
	--checked left to right. must have a 1 (100% chance⁘). use -1 for 0% chance.
	split"0.8,1", --just asteroids
	split"0.4,0.8,1", --asteroids and reds
	split"0.4,0.6,0.8,0.9,1", --asteroids, reds, blues, and ufos
	split"0.5,-1,0.8,-1,-1,1", --asteroids and reds (+shooting)
	split"0.8,-1,-1,-1,-1,0.9,1", --asteroids, shooting reds/blues
	split"0.6,-1,0.7,0.8,-1,0.9,1", --asteroids, reds/blues (+shooting)
	split"0.4,-1,-1,-1,0.5,0.75,1", --asteroids, shooting reds/blues, ufos
	split"-1,-1,-1,-1,1", --oops all ufos
}
--⁘ technically, 100% chance would be whatever number is immediately below 1.0
--  in the 32-bit fixed-point numbering system that pico-8 uses, but it doesn't
--  matter.
for lvl,probs in pairs(ENEMY_PROBABILITIES) do
	assert(#probs<=7,
		"too many probabilities for level "..lvl)
	for i=#probs,1,-1 do
		if probs[i]!=-1 then
			assert(probs[i]==1,
				"level "..lvl.."'s probabilities don't end with 1 (for 100% chance)")
			break
		end
	end
end

LAST_LEVEL=#ENEMY_PROBABILITIES+1

function update_game()
	t+=1
	jc.spr, jc.sx,jc.sy=
		t\2%3+1, 0,0
	if(btn(⬅️))jc.sx-=2
	if(btn(➡️))jc.sx+=2
	if(btn(⬆️))jc.sy-=2
	if(btn(⬇️))jc.sy+=2
	if
		((btn(🅾️) or btn(❎)) and no_shoot_until_t<=t)
		or btnp(🅾️) or btnp(❎)
	then
		add_entity{
			kind="pshot",
			x=jc.x, y=jc.y,
			sy=-3,
			spr=4,
		}
		no_shoot_until_t=t+5
	end

	WARP_LENGTH=180
	WARP_PEAK=WARP_LENGTH-160
	if level_warp_t>=t then
		star_speed_scale=max(
			star_speed_scale*((level_warp_t-t)>=WARP_PEAK and 1.05 or 0.5),
			0.5
		)
		if(level_warp_t==t)init_next_level()
	else
		if t>=level_soft_end_t and level!=LAST_LEVEL then
			local enemy_count=0
			for ent in all(entities) do
				if(ent.kind=="enemy")enemy_count+=1
			end
			if enemy_count==0 then
				level_warp_t=t+WARP_LENGTH
				add_score(level*100,jc.x,jc.y)
			end
		elseif t==entity_spawn_t then
			if level==LAST_LEVEL then
				kolob=add_entity{
					x=64, y=-64,
					spr=-1, preserve_offscreen=true,
					start_time=t,
					update=function(self)
						--allow the player to speed it up a bit.
						local dist_past=max(self.y,16)-jc.y
						if dist_past>0 then
							self.y+=dist_past
							if jc.y<self.y then
								jc.y=self.y
							end
						end
						self.sy=(t-self.start_time)/60
						if self.y>=63 then
							self.y,self.sy,self.update=63,0
							draw_game()
							end_game()
						end
					end,
				}
			else
				local randnum,enemy_prototype=rnd(1)
				for i=1,#ENEMY_PROBABILITIES[level] do
					if randnum<=ENEMY_PROBABILITIES[level][i] then
						enemy_prototype=ENEMIES[i]
						break
					end
				end
				assert(enemy_prototype,"missed a probability?")
				local enemy=add_entity(copy(enemy_prototype,{
					kind="enemy",
					x=ENTITY_MAX_LEFT+rnd(ENTITY_MAX_RIGHT-ENTITY_MAX_LEFT),
					y=-8,
				}))
				if(enemy.init)enemy:init()
				entity_spawn_t=t+10+flr(rnd(20))
			end
		end
	end

	for ent in all(entities) do
		if(ent.update)ent:update()
		ent.x+=ent.sx
		ent.y+=ent.sy
		if not ent.preserve_offscreen and ent_is_offscreen(ent) then
			del(entities,ent)
		end
	end
	for ent in all(entities) do
		ent.invuln_time_left=max(ent.invuln_time_left-1,0)
		if ent.kind=="enemy" and ent.invuln_time_left==0 then
			for pshot in all(entities) do
				if pshot.kind=="pshot" and entcol(ent,pshot) then
					del(entities,pshot)
					explode_at(pshot.x,pshot.y,2)
					ent.hp-=1
					if ent.hp>0 then
						ent.white_until_t=t+2
					else
						add_score(ent.score or 1,ent.x,ent.y)
						del(entities,ent)
						explode_at(ent.x,ent.y)
					end
					goto next_ent
				end
			end
			if entcol(ent,jc) then
				add_score(-100,jc.x,jc.y)
				jc.invuln_time_left=30
				explode_at(jc.x,jc.y,10)
			end
		end
		::next_ent::
	end

	--wrap x, clamp y
	if(jc.x<-4)jc.x=128+4
	if(jc.x>128+4)jc.x=-4
	jc.y=mid(ENTITY_MAX_LEFT,jc.y,ENTITY_MAX_RIGHT)
end

ENTITY_MAX_LEFT,ENTITY_MAX_RIGHT=4,124

function draw_game()
	--bg
	cls(0)
	draw_stars()
	_draw_kolob()

	--hud
	print(_get_score_text(), 0,0, 7)
	if t<=level_warp_t then
		local level_text="level "..level+1
		print_center(level_text,60)
	elseif t>=level_soft_end_t and level!=LAST_LEVEL then
		local warp_text="clear all to warp"
		print(warp_text, 128-#warp_text*4,0)
	end

	--entities
	foreach(entities,_draw_ent)
	_draw_ent(jc)

	--vfx
	for exp in all(explosions) do
		circfill(exp.x-exp.r\2,exp.y-exp.r\2, exp.r, 7)
		exp.r*=0.8
		if exp.r<1 then
			del(explosions,exp)
		end
	end
	for popup in all(popups) do
		print(popup.msg, popup.x,popup.y, 7)
		popup.timer-=1
		if popup.timer<=0 then
			del(popups,popup)
		end
	end
end

function end_game()
	_update,_draw=ending
	end_timer=0
end

function ending()
	end_timer+=1

	--bg
	cls(0)
	if end_timer<130 then
		draw_stars(true)
		_draw_kolob()
	end

	--entities
	if(end_timer<115)_draw_ent(jc)

	--end text
	if end_timer<100 then
		print_center("finish",52, 0)
		if end_timer>60 then
			end_timer=100
		end
	end

	if end_timer>=160 then
		print_center("thus ascended jesus.",36, 7)
		print_center("the end",44, 7)
		print_center("final score: ".._get_score_text(),60)
		print_center("time: ".._get_time_text(),68)
		if _press_to"reset" then
			extcmd"reset"
		end
	end
end

function _draw_ent(ent)
	if(ent.spr<0)return
	if (ent.invuln_time_left>0 and t%2==0) or ent.white_until_t>=t then
		--flashing effect
		for c=0,15 do pal(c,7) end
	else
		pal(ent.pal)
	end
	palt(ent.palt or 0b1000000000000000)
	spr(ent.spr, ent.x-4,ent.y-4, 1,1, ent.flip_x,ent.flip_y)
end

function _draw_kolob()
	if kolob then
		local frame=t\2%3
		circfill(kolob.x,kolob.y, 64, 5)
		circfill(kolob.x,kolob.y, frame==0 and 60 or 62, 6)
		circfill(kolob.x,kolob.y, frame==2 and 60 or 58, 7)
	end
end

function _get_score_text()
	local score_text=tostr(score,0x2).."0"
	while(#score_text<6)score_text="0"..score_text
	return score_text
end

function _get_time_text()
	local frames=t
	local secs=t\30
	frames-=secs*30
	local mins=secs\60
	secs-=mins*60
	local hrs=mins\60
	mins-=hrs*60
	if(mins<10)mins="0"..mins
	if(secs<10)secs="0"..secs
	frames*=10
	frames\=3
	if(frames<10)frames="0"..frames
	return hrs..":"..mins..":"..secs.."."..frames
end

function _press_to(what)
	print_center("press anything",84)
	print_center("to "..what,92)
	return btnp(🅾️) or btnp(❎)
end

-->8
--entity stuff

function add_entity(props)
	return copy_to(add(entities,{
		x=0,y=0,
		sx=0,sy=0,
		spr=0,
		hp=0,
		invuln_time_left=0, white_until_t=0,
	}),props)
end

function shoot(x,y,direction)
	SHOT_PAL_ANIM={
		0b1011111111111111,
		0b1101111111111111,
		0b1001111111111111,
	}
	add_entity{
		kind="enemy",
		x=x, y=y,
		spr=37, pal={8,8},
		score=0,
		direction=direction,
		update=function(self)
			self.x+=self.direction[1]*1.5
			self.y+=self.direction[2]*1.5
			self.palt=SHOT_PAL_ANIM[t\2%3+1]
		end,
	}
end

--returns true if the two entities are overlapping and both are vulnerable.
function entcol(a,b)
	return a.invuln_time_left==0 and b.invuln_time_left==0
	and a.x+3>=b.x-4 and a.x-4<=b.x+3
	and a.y+3>=b.y-4 and a.y-4<=b.y+3
end

function ent_is_offscreen(ent)
	return ent.x<-8 or ent.x>136
	or ent.y<-8 or ent.y>136
end

function direction_from_ent_to_ent(a,b)
	local x,y=b.x-a.x,b.y-a.y
	--normalize vector.
	--numbers are small! but numbers are big!! need to shift them so they less big!!!!!
	local len=sqrt((x>>4)^2+(y>>4)^2)<<4
	if(len==0)return {0,0}
	x/=len
	y/=len
	return {x,y}
end
function move_ent_toward_ent(a,b,amt)
	local x,y=unpack(direction_from_ent_to_ent(a,b))
	a.x+=x*amt
	a.y+=y*amt
end

-->8
--vfx
STAR_COLORS={1,1,1,5,5,6}
STAR_SPEEDS={0.125,[5]=0.25,[6]=0.5}

function generate_stars()
	for i=1,100 do
		add(stars,{
			x=rnd(128), y=flr(rnd(128))+star_spawn_y,
			c=rnd(STAR_COLORS)
		})
	end
end

function draw_stars(keep_still)
	pal()
	for star in all(stars) do
		local old_y=flr(star.y)
		if not keep_still then
			star.y+=STAR_SPEEDS[star.c]*star_speed_scale
		end
		line(
			star.x, flr(star.y)>old_y and old_y+1 or star.y,
			star.x, star.y,
			star.c
		)
		while star.y>star_spawn_y+128 do
			star.y-=128
			star.x=rnd(128)
			line(
				star.x, star_spawn_y,
				star.x, star.y,
				star.c
			)
		end
	end
end

function explode_at(x,y,r)
	return add(explosions,{
		x=x, y=y,
		r=r or 4,
	})
end

function add_score(addition,popup_x,popup_y)
	--addition can be negative.
	--see SCORE_SHIFT for an explanation of the shift.
	score=max(score+(addition>>SCORE_SHIFT),0)
	add(popups,{
		x=popup_x, y=popup_y,
		timer=30,
		msg=addition..(addition==0 and "" or "0"),
	})
end

-->8
--util

--doesn't handle full-width chars (i.e., 8px wide instead of 4px).
function print_center(s,...)
	print(s,64-#s*2,...)
end

function lerp(from,to,amt)
	return from+(to-from)*amt
end

function copy(...)
	local dest={}
	for src in all({...}) do
		copy_to(dest,src)
	end
	return dest
end
function copy_to(dest,src)
	for k,v in pairs(src) do
		dest[k]=v
	end
	return dest
end

function log(msg)
	local tstr,dec_part_str=unpack(split(tostr(time()),".",false))
	tstr ..= "."..sub((dec_part_str or "").."0000",1,4)
	printh(tstr..": "..msg,"log.txt")
end

__gfx__
00000000000440000004400000044000000990000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000004444000044440000444400000990000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00700700004ff400004ff400004ff400009aa9000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00077000007447000074470000744700009aa9000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00077000077777700777777007777770000990000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00700700077777700777777007777770000990000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000777777777777777777777777000990000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000007777777770077777777700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00044000004444000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0044440000ffff000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
004ff40000ffff000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00744700005555000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
07777770055555500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
07777770505555050000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
77777777d055550d0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
7777777700d00d000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00555500000055500090090000900900000660000001100000000000000000000000000000000000000000000000000000000000000000000000000000000000
00544550055554550898898008988980006666000110011000000000000000000000000000000000000000000000000000000000000000000000000000000000
05544450554444450888888008888880006116000102201000000000000000000000000000000000000000000000000000000000000000000000000000000000
05544450544444450828828008288280066116601022220100000000000000000000000000000000000000000000000000000000000000000000000000000000
55444455544444450888888008888880055665501022220100000000000000000000000000000000000000000000000000000000000000000000000000000000
55444445555544550082280000822800666556660102201000000000000000000000000000000000000000000000000000000000000000000000000000000000
05544455005555500888888008888880566666650110011000000000000000000000000000000000000000000000000000000000000000000000000000000000
00555550000055008008800808800880001551000001100000000000000000000000000000000000000000000000000000000000000000000000000000000000
