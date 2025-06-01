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
	for i=1,ox(btn) and 5 or 1 do
		_intro()
	end
end

function _intro()
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

	if t<=45 then
		camera()
		print("\#7hold 🅾️/❎ to skip", 8,120, 0)
	end
end

function init_game()
	--level gets immediately incremented before we start.
	_update,_draw,score,level=update_game,draw_game,0,0
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
	level_warp_t, level_soft_end_t,entity_spawn_t, no_shoot_until_t=
		0,
		t+(level==LAST_LEVEL-1 and 91 or 30*20), t+90,
		0
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
		{ --boss
			__kind="boss",
			spr=42, spr_layout="2x2",
			hp=20, max_hp=20,
			score=50,
			invuln_time_on_hit=5,
			ignore_damage=true,
			action="descend", timer=30,
			heads={},
			--palettes: 14,8; 10;11
			init=function(self)
				boss,self.x=self,63
			end,
			update=function(self)
				self.timer-=1
				local this_action,this_timer=self.action,self.timer
				if this_action=="descend" then
					self.y+=1
					if self.y>=63 then
						self.y=63
						self.action,self.timer="spawn heads",30
					end
				elseif this_action=="spawn heads" then
					if this_timer==29 then
						self.heads={}
						BOSS_HEAD_STARTING_OFFSET_X,
						BOSS_HEAD_STARTING_OFFSET_Y=
							split"4,0,0,0,0,0,-4",
							split"20,32,40,48,40,32,20"
						for i=0,6 do
							add(self.heads,make_entity{
								kind="enemy",
								x=self.x-52+16*i+BOSS_HEAD_STARTING_OFFSET_X[i+1], y=self.y-BOSS_HEAD_STARTING_OFFSET_Y[i+1],
								spr=38, palt=0b0000000000000001,
								hp=5,
								segments_to_draw=1,
							})
						end
					elseif this_timer>0 and this_timer%3==0 then
						for head in all(self.heads) do
							head.segments_to_draw+=1
							if head.segments_to_draw>7 then
								head.segments_to_draw-=1
								if(count(entities,head)==0)add(entities,head)
							end
						end
					elseif this_timer==0 then
						self.action,self.timer="heads shoot",45
					end
				elseif this_action=="move heads" then
					for head in all(self.heads) do
						head.start_x,head.start_y, head.target_x,head.target_y, head.spr=
							head.x,head.y,
							8+rnd(112),16+rnd(64),
							41
						head.flip_x=head.target_x<head.x
					end
					self.action,self.timer="move heads 2",45
					self:update_dead_heads()
				elseif this_action=="move heads 2" then
					if this_timer==0 then
						self.action,self.timer="heads shoot",30
					else
						for head in all(self.heads) do
							if this_timer>=15 then
								head.x,head.y=
									lerp(head.target_x,head.start_x,(this_timer-15)/30),
									lerp(head.target_y,head.start_y,(this_timer-15)/30)
							else
								head.spr=38
							end
						end
					end
					self:update_dead_heads()
				elseif this_action=="heads shoot" then
					if this_timer==0 then
						self.action="move heads"
					else
						for head in all(self.heads) do
							if this_timer==29 then
								head.spr=39
							elseif this_timer==27 then
								head.spr=40
							elseif this_timer==25 and head.hp>0 then
								shoot(head.x,head.y,direction_from_ent_to_ent(head,jc),true)
							elseif this_timer<12 then
								head.spr=this_timer==11 and 39 or 38
							end
						end
					end
					self:update_dead_heads()
				elseif this_action=="open eye" then
					if this_timer==20 then
						star_color_override, self.spr_layout_use_next_for_lower,self.ignore_damage=
							{2,[5]=5,[6]=8}, true
					elseif this_timer==10 then
						self.spr,self.spr_layout_use_next_for_lower=43
					elseif this_timer==0 then
						self.action,self.timer="eye wait",30
					end
				elseif this_action=="close eye" then
					if this_timer==20 then
						self.spr,self.spr_layout_use_next_for_lower=42,true
					elseif this_timer==10 then
						self.ignore_damage,self.spr_layout_use_next_for_lower, star_color_override=
							true
					elseif this_timer==0 then
						self.action,self.timer="spawn heads",30
					end
				elseif this_action=="eye shoot" then
					if this_timer%3==0 then
						local lookahead={
							x=jc.x+jc.sx*30,
							y=jc.y+jc.sy*30,
						}
						shoot(self.x,self.y,direction_from_ent_to_ent(self,lookahead),true)
					end
					if this_timer==0 then
						self.action,self.timer="eye wait",30
					end
				elseif this_action=="eye wait" then
					if this_timer==0 then
						if rnd(20)<self.hp then
							self.action,self.timer="eye shoot",60
						else
							self.action,self.timer="close eye",30
						end
					end
				end
			end,
			update_dead_heads=function(self)
				for head in all(self.heads) do
					if t%3==0 and head.hp<=0 then
						head.segments_to_draw-=1
						if head.segments_to_draw<=0 then
							del(self.heads,head)
						end
					end
				end
				if #self.heads==0 then
					self.action,self.timer="open eye",30
				end
			end,
			draw=function(self)
				for head in all(self.heads) do
					local dist_x,dist_y=head.x-self.x,head.y-self.y
					dist_x/=7 dist_y/=7
					for i=1,head.segments_to_draw-1 do
						_draw_ent{
							x=self.x+dist_x*i,
							y=self.y+dist_y*i,
							spr=54,
							--these have to exist.
							invuln_time_left=0,white_until_t=0,
						}
					end
				end
				for head in all(self.heads) do
					if(count(entities,head)>0)_draw_ent(head)
				end
			end,
		},
	}
end

--per level.
ENEMY_PROBABILITIES={
	--asteroid, +swaying, red, blue, ufo, red(shoot), blue(shoot), boss.
	--checked left to right. must have a 1 (100% chance⁘). use -1 for 0% chance.
	split"0.8,1", --just asteroids
	split"0.4,0.8,1", --asteroids and reds
	split"0.4,0.6,0.8,0.9,1", --asteroids, reds, blues, and ufos
	split"0.5,-1,0.8,-1,-1,1", --asteroids and reds (+shooting)
	split"0.8,-1,-1,-1,-1,0.9,1", --asteroids, shooting reds/blues
	split"0.6,-1,0.7,0.8,-1,0.9,1", --asteroids, reds/blues (+shooting)
	split"0.4,-1,-1,-1,0.5,0.75,1", --asteroids, shooting reds/blues, ufos
	split"-1,-1,-1,-1,1", --oops all ufos
	split"-1,-1,-1,-1,-1,-1,-1,1", --boss
}
--⁘ technically, 100% chance would be whatever number is immediately below 1.0
--  in the 32-bit fixed-point numbering system that pico-8 uses, but it doesn't
--  matter.
for lvl,probs in pairs(ENEMY_PROBABILITIES) do
	assert(#probs<=8,
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
		ox(btn) and no_shoot_until_t<=t
		or ox(btnp)
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
				add_score(level*10,jc.x,jc.y)
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
				log("spawned "..(enemy.__kind or enemy.kind))
			end
		end
	end

	for ent in all(entities) do
		if(ent.update)ent:update()
		ent.x+=ent.sx
		ent.y+=ent.sy
		if not ent.preserve_offscreen and ent_is_offscreen(ent) then
			del(entities,ent)
			log("deleted offscreen "..(ent.__kind or ent.kind))
		end
	end
	for ent in all(entities) do
		ent.invuln_time_left=max(ent.invuln_time_left-1,0)
		if ent.kind=="enemy" and ent.invuln_time_left==0 and not ent.ignore_damage then
			for pshot in all(entities) do
				if pshot.kind=="pshot" and entcol(ent,pshot) then
					del(entities,pshot)
					explode_at(pshot.x,pshot.y,2)
					ent.hp-=1
					if ent.hp>0 then
						ent.white_until_t=t+2
						if ent.invuln_time_on_hit then
							ent.invuln_time_left=ent.invuln_time_on_hit
						end
					else
						add_score(ent.score or 1,ent.x,ent.y)
						del(entities,ent)
						explode_at(ent.x,ent.y)
						if ent==boss then
							boss,star_color_override=nil
						end
					end
					goto next_ent
				end
			end
			if entcol(ent,jc) then
				add_score(-100,jc.x,jc.y)
				if boss then
					add_popup("+5🐱",jc.x,jc.y)
					boss.hp=min(boss.hp+5,boss.max_hp)
				else
					add_popup("+5⧗",jc.x,jc.y)
					level_soft_end_t=max(level_soft_end_t,t)
					level_soft_end_t=min(level_soft_end_t+5*30,t+20*30)
					if entity_spawn_t<=t then
						entity_spawn_t=t+30
					end
				end
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
	--the spaces after symbols are to save tokens in my implementation.
	if t<=level_warp_t then
		local level_text="level "..level+1
		print_center(level_text,60)
	elseif level==LAST_LEVEL-1 then
		print_right(
			boss and boss.hp.."🐱 " or "",
			0
		)
	elseif t<level_soft_end_t then
		print_right(
			ceil((level_soft_end_t-t)/30).."⧗ ",
			0
		)
	elseif t>=level_soft_end_t and level!=LAST_LEVEL then
		print_right("clear all to warp",0)
	end

	--entities
	for ent in all(entities) do
		_draw_ent(ent)
		if(ent.draw)ent:draw()
	end
	_draw_ent(jc) --so it's on top

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
	if(ent.spr==-1)return
	if (ent.invuln_time_left>0 and t%2==0) or ent.white_until_t>=t then
		--flashing effect
		for c=0,15 do pal(c,7) end
	else
		pal(ent.pal)
	end
	palt(ent.palt or 0b1000000000000000)
	local draw=function(x,y,flip_x,flip_y)
		spr(ent.spr,
			ent.x-4+x,ent.y-4+y,
			1,1,
			flip_x,flip_y)
	end
	local layout=ent.spr_layout
	if layout then
		if layout=="1x2" then
			draw(-4,0)
			draw(4,0,true)
		elseif layout=="2x2" then
			draw(-4,-4)
			draw(4,-4,true)
			if(ent.spr_layout_use_next_for_lower)ent.spr+=1
			draw(-4,4,false,true)
			draw(4,4,true,true)
			if(ent.spr_layout_use_next_for_lower)ent.spr-=1
		else
			assert(false,"unknown sprite layout: "..layout)
		end
	else
		draw(0,0,ent.flip_x,ent.flip_y)
	end
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
	return ox(btnp)
end

function ox(btn_or_btnp)
	return btn_or_btnp(🅾️) or btn_or_btnp(❎)
end

-->8
--entity stuff

function add_entity(props)
	return add(entities,make_entity(props))
end
function make_entity(props)
	return copy_to({
		x=0,y=0,
		sx=0,sy=0,
		spr=0,
		hp=0,
		invuln_time_left=0, white_until_t=0,
	},props)
end

function shoot(x,y,direction,is_fire)
	SHOT_PAL_ANIM={
		0b1011111111111111,
		0b1101111111111111,
		0b1001111111111111,
	}
	FIRE_SPR_ANIM={55,56}
	local speed=is_fire and 3 or 1.5
	add_entity{
		kind="enemy",
		x=x, y=y,
		spr=37, pal=not is_fire and {8,8},
		hp=is_fire and 2 or 1,
		score=0,
		direction=direction,
		update=function(self)
			self.x+=self.direction[1]*speed
			self.y+=self.direction[2]*speed
			if is_fire then
				self.spr=FIRE_SPR_ANIM[t\2%2+1]
			else
				self.palt=SHOT_PAL_ANIM[t\2%3+1]
			end
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
			star_color_override and star_color_override[star.c] or star.c
		)
		while star.y>star_spawn_y+128 do
			star.y-=128
			star.x=rnd(128)
			line(
				star.x, star_spawn_y,
				star.x, star.y,
				star_color_override and star_color_override[star.c] or star.c
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
	add_popup(addition==0 and addition or addition.."0", popup_x,popup_y)
end

function add_popup(msg,x,y)
	::look_for_an_overlap::
	for popup in all(popups) do
		if popup.x==x and popup.y==y then
			y-=8
			goto look_for_an_overlap
		end
	end
	add(popups,{x=x,y=y,msg=msg,timer=30})
end

-->8
--util

--these don't handle 8px wide chars (instead of the normal 4px), such as
--symbols. if you have one at the end, just put a space after it.
function print_center(s,...)
	print(s,64-#s*2,...)
end
function print_right(s,...)
	print(s,128-#s*4,...)
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
005555000000555000900900009009000006600000011000f9ffff9fffffffffffffffffff9fffff005025000050250000000000000000000000000000000000
005445500555545508988980089889800066660001100110f992299fff9229ffff8888ffff99ffff002222200022222000000000000000000000000000000000
055444505544444508888880088888800061160001022010f298892ff208802ff872278f8899ffff522222225222222200000000000000000000000000000000
05544450544444450828828008288280066116601022220128088082287887822270072228088fff522222225222222200000000000000000000000000000000
5544445554444445088888800888888005566550102222012888888222722722200000022888888f022222220222222200000000000000000000000000000000
55444445555544550082280000822800666556660102201028788782200000022000000228888788002222550022225500000000000000000000000000000000
055444550055555008888880088888805666666501100110f272272ff200002ff200002f2227272f02222555022225e800000000000000000000000000000000
005555500000550080088008088008800015510000011000ff2222ffff2222ffff2222ffff2222ff5222255552222e8800000000000000000000000000000000
00000000000000000000000000000000000000000000000000022000009099000000900000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000228822009a9aa90090a900000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000288882099a9aa90999a999000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000288888829aa9a99999a9aa9900000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000288888829aaaa999999aaa9900000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000288882099aa99a0999aaa9000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000228822009999a900999999000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000022000009999000099990000000000000000000000000000000000000000000000000000000000
