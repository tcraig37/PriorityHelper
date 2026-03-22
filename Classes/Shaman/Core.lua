-- Classes/Shaman/Core.lua
-- Priority rotation logic for Shaman specs (3.3.5a compatible)
-- Uses core RunSimulation for CD-aware predictions

local DH = PriorityHelper
if not DH then return end

if select(2, UnitClass("player")) ~= "SHAMAN" then
    return
end

local ns = DH.ns
local class = DH.Class
local state = DH.State

-- ============================================================================
-- ENHANCEMENT ROTATION
-- ============================================================================

local enhancementConfig = {
    gcdType = "melee",
    maxRecs = 3,
    allowDupes = true,
    cds = {
        stormstrike = "stormstrike",
        lava_lash = "lava_lash",
        feral_spirit = "feral_spirit",
        shamanistic_rage = "shamanistic_rage",
        flame_shock = "flame_shock",
        earth_shock = "earth_shock",
        fire_nova = "fire_nova",
    },
    baseCDs = {
        stormstrike = 8,
        lava_lash = 6,
        feral_spirit = 180,
        shamanistic_rage = 60,
        flame_shock = 6,   -- shared shock CD
        earth_shock = 6,   -- shared shock CD
        fire_nova = 10,
    },
    auras = {
        { up = "flame_shock_up", remains = "flame_shock_remains" },
        { up = "stormstrike_up", remains = "stormstrike_remains" },
    },
    initState = function(sim, s)
        -- Maelstrom Weapon stacks
        sim.mw_stacks = s.buff.maelstrom_weapon.stacks or 0

        -- DoTs/debuffs
        sim.flame_shock_up = s.debuff.flame_shock.up
        sim.flame_shock_remains = s.debuff.flame_shock.remains
        sim.stormstrike_up = s.debuff.stormstrike.up
        sim.stormstrike_remains = s.debuff.stormstrike.remains

        -- Buffs
        sim.ls_up = s.buff.lightning_shield.up

        -- Talents
        sim.has_stormstrike = s.talent.stormstrike.rank > 0
        sim.has_lava_lash = s.talent.lava_lash.rank > 0
        sim.has_mw = s.talent.maelstrom_weapon.rank > 0
        sim.has_feral_spirit = s.talent.feral_spirit.rank > 0
        sim.has_shamanistic_rage = s.talent.shamanistic_rage.rank > 0
        sim.has_improved_stormstrike = s.talent.improved_stormstrike.rank > 0
        sim.has_fire_nova = s.talent.improved_fire_nova.rank > 0
    end,
    getPriority = function(sim, recs)
        -- Feral Spirit (major CD)
        if sim.has_feral_spirit and sim:ready("feral_spirit") and not DH:IsSnoozed("feral_spirit") then
            return "feral_spirit"
        end

        -- Shamanistic Rage (mana recovery)
        if sim.has_shamanistic_rage and sim.mana_pct < 30 and sim:ready("shamanistic_rage") then
            return "shamanistic_rage"
        end

        -- Lightning Shield if not up
        if not sim.ls_up then
            return "lightning_shield"
        end

        -- Maelstrom Weapon 5 stacks: instant Lightning Bolt
        if sim.has_mw and sim.mw_stacks >= 5 then
            return "lightning_bolt"
        end

        -- Stormstrike on CD
        if sim.has_stormstrike and sim:ready("stormstrike") then
            return "stormstrike"
        end

        -- Flame Shock: maintain DoT
        if (not sim.flame_shock_up or sim.flame_shock_remains < 2) and sim:ready("flame_shock") and sim.ttd > 6 then
            return "flame_shock"
        end

        -- Earth Shock: when Flame Shock is healthy and shock CD is up
        if sim.flame_shock_up and sim.flame_shock_remains > 6 and sim:ready("earth_shock") then
            return "earth_shock"
        end

        -- Fire Nova (if near fire totem)
        if sim.has_fire_nova and sim:ready("fire_nova") then
            return "fire_nova"
        end

        -- Lava Lash
        if sim.has_lava_lash and sim:ready("lava_lash") then
            return "lava_lash"
        end

        -- Nothing ready - wait
        return nil
    end,
    onCast = function(sim, key)
        if key == "flame_shock" then
            sim.flame_shock_up = true
            sim.flame_shock_remains = 18
            -- Shared shock CD: put earth shock on CD too
            sim.cd["earth_shock"] = sim.cd["flame_shock"]
        elseif key == "earth_shock" then
            -- Shared shock CD: put flame shock on CD too
            sim.cd["flame_shock"] = sim.cd["earth_shock"]
        elseif key == "stormstrike" then
            sim.stormstrike_up = true
            sim.stormstrike_remains = 12
        elseif key == "lightning_bolt" then
            sim.mw_stacks = 0  -- consume MW stacks
        elseif key == "lightning_shield" then
            sim.ls_up = true
        elseif key == "shamanistic_rage" then
            sim.mana_pct = math.min(100, sim.mana_pct + 30)
        end
    end,
    getWaitTime = function(sim)
        -- Find the nearest CD
        local nearest = 999
        local keys = { "stormstrike", "lava_lash", "flame_shock", "earth_shock", "fire_nova" }
        for _, key in ipairs(keys) do
            local cd = sim.cd[key] or 0
            if cd > 0 and cd < nearest then
                nearest = cd
            end
        end
        if nearest < 999 then
            return nearest
        end
        return sim.gcd
    end,
}

local function GetEnhancementRecommendations(addon)
    return DH:RunSimulation(state, enhancementConfig)
end

-- ============================================================================
-- ELEMENTAL ROTATION
-- ============================================================================

local elementalConfig = {
    gcdType = "spell",
    maxRecs = 3,
    allowDupes = true,
    cds = {
        lava_burst = "lava_burst",
        chain_lightning = "chain_lightning",
        flame_shock = "flame_shock",
        earth_shock = "earth_shock",
        elemental_mastery = "elemental_mastery",
        natures_swiftness = "natures_swiftness",
        thunderstorm = "thunderstorm",
    },
    baseCDs = {
        lava_burst = 8,
        chain_lightning = 6,
        flame_shock = 6,
        earth_shock = 6,
        elemental_mastery = 180,
        natures_swiftness = 180,
        thunderstorm = 45,
    },
    auras = {
        { up = "flame_shock_up", remains = "flame_shock_remains" },
    },
    initState = function(sim, s)
        -- DoTs
        sim.flame_shock_up = s.debuff.flame_shock.up
        sim.flame_shock_remains = s.debuff.flame_shock.remains

        -- Buffs
        sim.clearcasting = s.buff.clearcasting.up
        sim.ls_up = s.buff.lightning_shield.up

        -- Talents
        sim.has_lava_burst = s.talent.lava_flows.rank > 0 or true  -- all ele have LvB
        sim.has_em = s.talent.elemental_mastery.rank > 0
        sim.has_ns = s.talent.natures_swiftness.rank > 0
        sim.has_thunderstorm = s.talent.thunderstorm.rank > 0
        sim.has_storm_earth_fire = s.talent.storm_earth_and_fire.rank or 0
    end,
    getPriority = function(sim, recs)
        -- Elemental Mastery (major CD)
        if sim.has_em and sim:ready("elemental_mastery") and not DH:IsSnoozed("elemental_mastery") then
            return "elemental_mastery"
        end

        -- Lightning Shield if not up
        if not sim.ls_up then
            return "lightning_shield"
        end

        -- Flame Shock: must be up for Lava Burst auto-crit
        if (not sim.flame_shock_up or sim.flame_shock_remains < 2) and sim:ready("flame_shock") and sim.ttd > 6 then
            return "flame_shock"
        end

        -- Lava Burst on CD (guaranteed crit with Flame Shock up)
        if sim:ready("lava_burst") and sim.flame_shock_up then
            return "lava_burst"
        end

        -- Chain Lightning (if off CD, good DPS filler between LvB)
        if sim:ready("chain_lightning") then
            return "chain_lightning"
        end

        -- Filler: Lightning Bolt
        return "lightning_bolt"
    end,
    onCast = function(sim, key)
        if key == "flame_shock" then
            sim.flame_shock_up = true
            sim.flame_shock_remains = 18
            -- Shared shock CD
            sim.cd["earth_shock"] = sim.cd["flame_shock"]
        elseif key == "earth_shock" then
            sim.cd["flame_shock"] = sim.cd["earth_shock"]
        elseif key == "elemental_mastery" then
            -- Next cast is instant + crit
        elseif key == "lightning_shield" then
            sim.ls_up = true
        end
    end,
    getAdvanceTime = function(sim, action)
        local h = sim.haste or 1
        if action == "lightning_bolt" then return math.max(sim.gcd, 2.5 / h) end
        if action == "chain_lightning" then return math.max(sim.gcd, 2.0 / h) end
        if action == "lava_burst" then return math.max(sim.gcd, 2.0 / h) end
        return sim.gcd  -- instants: flame shock, earth shock, EM, LS, thunderstorm
    end,
}

local function GetElementalRecommendations(addon)
    return DH:RunSimulation(state, elementalConfig)
end

-- ============================================================================
-- ROTATION MODES
-- ============================================================================

DH:RegisterMode("enhancement", {
    name = "Enhancement (DPS)",
    icon = select(3, GetSpellInfo(17364)) or "Interface\\Icons\\Ability_Shaman_Stormstrike",
    rotation = function(addon)
        return GetEnhancementRecommendations(addon)
    end,
})

DH:RegisterMode("elemental", {
    name = "Elemental (DPS)",
    icon = select(3, GetSpellInfo(60043)) or "Interface\\Icons\\Spell_Shaman_LavaBurst",
    rotation = function(addon)
        return GetElementalRecommendations(addon)
    end,
})
