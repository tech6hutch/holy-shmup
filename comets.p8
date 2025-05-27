pico-8 cartridge // http://www.pico-8.com
version 42
__lua__
function _init()
	--reset log
	printh("-- start --","log.txt",true)
	--disable btnp repeat
	poke(0x5f5c,255)
	--disable print() autoscroll
	poke(0x5f36,0x40)

	--skip intro
	t=0 init_game() do return end

	_update,_draw=intro
	t,entities,stars,star_spawn_y=0,{},{},-300-64
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
	_draw_stars(true)
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
	_update,_draw,score=update_game,draw_game,0
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
	entities,explosions={},{}
	entity_spawn_t,no_shoot_until_t=t+90,0
	jc=add_entity{
		x=64,y=64,
		preserve_offscreen=true,
	}
end

function generate_stars()
	for i=1,100 do
		STAR_COLORS={1,1,1,5,5,6}
		add(stars,{
			x=rnd(128), y=rnd(128)+star_spawn_y,
			c=rnd(STAR_COLORS)
		})
	end
end

function _asteroid_update(self)
	self.y+=1
	self.flip_x,self.flip_y, self.spr=
		rnd{false,true},rnd{false,true},
		rnd{32,33}
end

ENEMIES={
	{ --asteroid 1 (comes straight down)
		hp=3,
		update=_asteroid_update,
	},
	{ --asteroid 2 (sways)
		hp=3,
		score=2,
		init=function(self)
			self.start_x,self.start_time,self.period,self.distance=self.x,time(),rnd(1),rnd(20)
		end,
		update=function(self)
			_asteroid_update(self)
			self.x=self.start_x+sin((time()-self.start_time)*self.period)*self.distance
		end,
	},
	{ --demon
		hp=5,
		score=2,
		timer=15,
		init=function(self)
			self.target=copy_to(jc)
		end,
		update=function(self)
			if self.target then
				self.spr=34
				move_ent_toward_ent(self,self.target,1)
				self.timer-=1
				if self.timer<=0 then
					self.timer,self.target=15
				end
			else
				self.spr=35
				self.timer-=1
				if self.timer<=0 then
					self.timer,self.target=15,copy_to(jc)
				end
			end
		end,
	},
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
				shot_pal_anim={
					0b1011111111111111,
					0b1101111111111111,
					0b1001111111111111,
				}
				add_entity{
					kind="enemy",
					x=self.x, y=self.y,
					spr=37, pal={8,8},
					score=0,
					direction=direction_from_ent_to_ent(self,jc),
					update=function(self)
						self.x+=self.direction[1]*1.5
						self.y+=self.direction[2]*1.5
						self.palt=shot_pal_anim[t\2%3+1]
					end,
				}
			elseif self.time_until_shoot<15 then
				self.pal[1]=7
			end
		end,
	},
}

ENEMY_PROBABILITIES={
	-- split"0.5,0.8,1",
	split"0.2,0.5,0.8,1",
}

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

	if t==entity_spawn_t then
		local randnum,enemy_prototype=rnd(1)
		for i=1,#ENEMY_PROBABILITIES[1] do
			if randnum<=ENEMY_PROBABILITIES[1][i] then
				enemy_prototype=ENEMIES[i]
				break
			end
		end
		assert(enemy_prototype,"missed a probability?")
		local enemy=add_entity(copy_to(enemy_prototype,{
			kind="enemy",
			x=ENTITY_MAX_LEFT+rnd(ENTITY_MAX_RIGHT-ENTITY_MAX_LEFT),
			y=-8,
		}))
		if(enemy.init)enemy:init()
		entity_spawn_t=t+10+flr(rnd(20))
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
						score+=ent.score or 1
						del(entities,ent)
						explode_at(ent.x,ent.y)
					end
					goto next_ent
				end
			end
			if entcol(ent,jc) then
				jc.invuln_time_left, score=
					30,
					max(score-100,0)
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
	cls(0)
	_draw_stars()
	print(sub("000000"..score,-6).."0", 0,0, 7)
	foreach(entities,_draw_ent)
	_draw_ent(jc)
	for exp in all(explosions) do
		circfill(exp.x-exp.r\2,exp.y-exp.r\2, exp.r, 7)
		exp.r*=0.8
		if exp.r<1 then
			del(explosions,exp)
		end
	end
end

function _draw_stars(keep_still)
	pal()
	for star in all(stars) do
		if(not keep_still)star.y+=1
		if star.y>star_spawn_y+128 then
			star.x,star.y=rnd(128),star_spawn_y-1
		end
		pset(star.x,star.y,star.c)
	end
end

function _draw_ent(ent)
	if (ent.invuln_time_left>0 and t%2==0) or ent.white_until_t>=t then
		--flashing effect
		for c=0,15 do pal(c,7) end
	else
		pal(ent.pal)
	end
	palt(ent.palt or 0b1000000000000000)
	spr(ent.spr, ent.x-4,ent.y-4, 1,1, ent.flip_x,ent.flip_y)
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
	local len=sqrt(x*x+y*y)
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
function explode_at(x,y,r)
	return add(explosions,{
		x=x, y=y,
		r=r or 4,
	})
end

-->8
--util
function lerp(from,to,amt)
	return from+(to-from)*amt
end

function copy_to(tbl,props)
	for k,v in pairs(props) do
		tbl[k]=v
	end
	return tbl
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
