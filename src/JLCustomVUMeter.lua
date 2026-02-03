local oo            = require("loop.simple")
local math          = require("math")

local Framework     = require("jive.ui.Framework")
local Icon          = require("jive.ui.Icon")
local Surface       = require("jive.ui.Surface")
local Timer         = require("jive.ui.Timer")
local Widget        = require("jive.ui.Widget")

local string           = require("jive.utils.string")
local vis        = require("jive.vis")

local debug         = require("jive.utils.debug")
local log           = require("jive.utils.log").logger("jivelite.vis")

-- VIS is optional. If not present, export a harmless stub widget so the applet still loads.
local _ok_vis, vis = pcall(require, "jive.vis")
if not _ok_vis or not vis then
    local JLNullVU = oo.class({}, Widget)
    function JLNullVU:__init(name, mode, channels)
        local o = Widget.__init(self, name)
        o.mode = mode
        o.channels = channels
        return oo.rawnew(self, o)
    end
    function JLNullVU:_layout() end
    function JLNullVU:draw(surface) end
    -- Export a constructor compatible with callers: JLNullVU("itemX", "analog|digital", "left|right|mono")
    return function(name, mode, channels) return JLNullVU(name, mode, channels) end
end

local FRAME_RATE    = jive.ui.FRAME_RATE

module(...)
oo.class(_M, Icon)


function __init(self, style, mode, channels)
	local obj = oo.rawnew(self, Icon(style))

	obj.mode = mode

	obj.cap = { 0, 0 }

	obj:addAnimation(function() obj:reDraw() end, FRAME_RATE)

	obj.images = nil

	obj.channels = channels or "left+right"

	return obj
end


function _skin(self)
	Icon._skin(self)
end


function setImage(self, id, image)
	if self.images == nil then
		self.images = {}
	end
	self.images[id] = image
-- If we just replaced the analog background, force a relayout
    if id == "background" then -- and self.mode == "analog" then <-- TODO check if we need this
        self:reLayout()
    end
end

function _layout(self)
	local x,y,w,h = self:getBounds()
	local l,t,r,b = self:getPadding()
    -- Allow any resolution; only bail on invalid sizes
    if w <= 0 or h <= 0 then
		return
	end

	if self.mode == "digital" and self.images and self.images["tickon"] then
		self.w = w - l - r
		self.h = h - t - b

		local tw,th = self.images["tickon"]:getSize()

		self.x1 = x + l + ((self.w - tw * 2) / 3)
		self.x2 = x + l + ((self.w - tw * 2) / 3) * 2 + tw

		self.bars = self.h / th
		self.y = y + t + (self.bars * th)

	elseif self.mode == "analog" then
		self.x1 = x
		self.x2 = x + (w / 2)
		self.y = y
		self.w = w / 2
		self.h = h
		
        -- Scale analog background every layout pass to fit region
        if self.images and self.images["background"] then
            local img = self.images["background"]
            local srcW, srcH = img:getSize()
            local frameW = srcW / 25
            local sX = self.w / frameW
            local sY = self.h / srcH
            local s  = math.min(sX, sY)
            if math.abs(s - 1.0) > 0.01 then
                if s < 0.01 then s = 0.01 end
                self.images["background"] = img:rotozoom(0, s, true)
            end
        end
	end
end


function draw(self, surface)
	if self.images ~= nil then
		if self.mode == "spectrum" then
			self.images["background"]:blit(surface, self:getBounds())
		end

		local sampleAcc = vis:vumeter()
		-- Uncomment to simulate in SqueezePlay
		-- sampleAcc = {}
		-- sampleAcc[1] = math.random(3227)
		-- sampleAcc[2] = math.random(3227)

		if string.find(self.channels,'^left') or self.channels == "mono" then
			_drawMeter(self, surface, sampleAcc, 1, self.x1, self.y, self.w, self.h)
		end
		if string.find(self.channels,'right$') then
			if string.find(self.channels,"^right") then
				_drawMeter(self, surface, sampleAcc, 2, self.x1, self.y, self.w, self.h)
			else
				_drawMeter(self, surface, sampleAcc, 2, self.x2, self.y, self.w, self.h)
			end
		end
	end
end


-- FIXME dynamic based on number of bars
local RMS_MAP = {
	0, 2, 5, 7, 10, 21, 33, 45, 57, 82, 108, 133, 159, 200, 
	242, 284, 326, 387, 448, 509, 570, 652, 735, 817, 900, 
	1005, 1111, 1217, 1323, 1454, 1585, 1716, 1847, 2005, 
	2163, 2321, 2480, 2666, 2853, 3040, 3227, 
}


function _drawMeter(self, surface, sampleAcc, ch, x, y, w, h)
	local val = 1
	for i = #RMS_MAP, 1, -1 do
		if sampleAcc[ch] > RMS_MAP[i] then
			val = i
			break
		end
	end

	-- FIXME when rms map scaled
	val = math.floor(val / 2)
	if val >= self.cap[ch] then
		self.cap[ch] = val
	elseif self.cap[ch] > 0 then
		if self.mode == "digital" then
			self.cap[ch] = self.cap[ch] - 0.5
		else
			self.cap[ch] = self.cap[ch] - 1
		end
	end

	if self.mode == "digital" and self.images ~= nil and self.bars and self.images["tickon"] then
		local tw,th = self.images["tickon"]:getSize()

		-- ── NEW: row-based drawing (no magic 272), normalized to self.bars ──
		local maxBars = math.floor(self.h / th)
		if maxBars < 1 then return end

		-- Map current value and cap to BAR units (0..maxBars)
		local maxMapUnits = (#RMS_MAP - 1) / 2    -- matches the existing "val = floor(val/2)"
		local function unitsToBars(u)
			if maxMapUnits <= 0 then return 0 end
			local b = math.floor((u / maxMapUnits) * maxBars + 0.5)
			if b < 0 then b = 0 elseif b > maxBars then b = maxBars end
			return b
		end
		local valBars = unitsToBars(val)

		-- Keep a DIGITAL-only cap in bar units (does not affect analog)
		self.capBars = self.capBars or { 0, 0 }
		if self.capBars[ch] == nil then self.capBars[ch] = 0 end
		local capBarsNow = unitsToBars(self.cap[ch] or 0)
		if capBarsNow >= (self.capBars[ch] or 0) then
			self.capBars[ch] = capBarsNow
		else
			self.capBars[ch] = self.capBars[ch] - 0.5
			if self.capBars[ch] < 0 then self.capBars[ch] = 0 end
		end
		local capRow = math.floor(self.capBars[ch] + 0.5)  -- single row to place tickcap

		-- Draw from bottom up, lighting 'valBars' rows and placing one cap
		local drewCap = false
		for i = 1, maxBars do
			if (not drewCap) and (i == capRow) and self.images["tickcap"] ~= nil then
				self.images["tickcap"]:blit(surface, x, y)
				drewCap = true
			elseif i <= valBars and self.images["tickon"] ~= nil then
				self.images["tickon"]:blit(surface, x, y)
			elseif self.images["tickoff"] ~= nil then
				self.images["tickoff"]:blit(surface, x, y)
			end
			y = y - th
		end

    elseif self.mode == "analog" and self.images and self.images["background"] then
        -- Correctly compute frame width for 25-frame analog sprite sheet
        local img    = self.images["background"]
        local srcW, srcH = img:getSize()
        local frameW = math.floor(srcW / 25)
        local idx    = math.floor(self.cap[ch])
        if idx >= 25 then idx = 24 end
        if idx < 0 then idx = 0 end
        local srcX = idx * frameW
        img:blitClip(srcX, 0, frameW, srcH, surface, x, y)
	end
end


--[[

=head1 LICENSE

Copyright 2010, Erland Isaksson (erland_i@hotmail.com)
Copyright 2010, Logitech, inc.
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:
    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * Neither the name of Logitech nor the
      names of its contributors may be used to endorse or promote products
      derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL LOGITECH, INC BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

=cut
--]]

