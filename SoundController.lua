-- SoundController
-- LocalScript: StarterPlayerScripts/SoundController
-- Client-side sound controller for BGM/SFX and settings.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local ContentProvider = game:GetService("ContentProvider")

local SoundConfig = require(ReplicatedStorage:WaitForChild("Config"):WaitForChild("SoundConfig"))

local DEBUG_MODE = false
local LOG_PREFIX = "[SoundController]"

local currentBGM = nil
local currentBGMKey = nil
local desiredBGMKey = nil
local sfxInstances = {}
local isInitialized = false
local eventsConnected = false

local soundSettings = {
	MusicEnabled = true,
	SfxEnabled = true,
}

local SoundEvents = nil

local function DebugLog(...)
	if DEBUG_MODE then
		print(LOG_PREFIX, ...)
	end
end

local function EnsureFolder(parent, name)
	local folder = parent:FindFirstChild(name)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = name
		folder.Parent = parent
	end
	return folder
end

local function GetOrCreateBGMSound(bgmKey)
	local config = SoundConfig.GetBGMConfig(bgmKey)
	if not config then
		warn(LOG_PREFIX, "Missing BGM config:", bgmKey)
		return nil
	end

	local bgmFolder = EnsureFolder(SoundService, "BGM")
	local subFolder = EnsureFolder(bgmFolder, bgmKey)

	local sound = subFolder:FindFirstChild(config.Name)
	if not sound then
		sound = Instance.new("Sound")
		sound.Name = config.Name
		sound.Parent = subFolder
	end

	sound.SoundId = config.SoundId
	sound.Volume = config.Volume or SoundConfig.Settings.BGMVolume
	sound.Looped = config.Looped ~= false

	return sound
end

local function GetOrCreateSFXSound(sfxKey)
	local config = SoundConfig.GetSFXConfig(sfxKey)
	if not config then
		warn(LOG_PREFIX, "Missing SFX config:", sfxKey)
		return nil
	end

	local audioFolder = EnsureFolder(SoundService, "Audio")
	local commonFolder = EnsureFolder(audioFolder, "Common")

	local sound = commonFolder:FindFirstChild(config.Name)
	if not sound then
		sound = Instance.new("Sound")
		sound.Name = config.Name
		sound.Parent = commonFolder
	end

	sound.SoundId = config.SoundId
	sound.Volume = config.Volume or SoundConfig.Settings.SFXVolume
	sound.Looped = config.Looped or false

	return sound
end

local function FadeOut(sound, duration, callback)
	if not sound then
		if callback then
			callback()
		end
		return
	end

	if not duration or duration <= 0 then
		sound:Stop()
		if callback then
			callback()
		end
		return
	end

	local tween = TweenService:Create(
		sound,
		TweenInfo.new(duration, Enum.EasingStyle.Linear),
		{ Volume = 0 }
	)

	tween.Completed:Connect(function()
		sound:Stop()
		if callback then
			callback()
		end
	end)

	tween:Play()
end

local function FadeIn(sound, targetVolume, duration)
	if not sound then
		return
	end

	if not duration or duration <= 0 then
		sound.Volume = targetVolume
		sound:Play()
		return
	end

	sound.Volume = 0
	sound:Play()

	local tween = TweenService:Create(
		sound,
		TweenInfo.new(duration, Enum.EasingStyle.Linear),
		{ Volume = targetVolume }
	)

	tween:Play()
end

local function StopAllSFX()
	for _, sound in pairs(sfxInstances) do
		if sound and sound.IsPlaying then
			sound:Stop()
		end
	end
end

local function StopBGMInternal(clearDesired)
	if currentBGM and currentBGM.IsPlaying then
		local fadeDuration = SoundConfig.Settings.BGMFadeDuration or 0
		FadeOut(currentBGM, fadeDuration, nil)
		DebugLog("Stop BGM:", currentBGMKey)
	end

	currentBGM = nil
	currentBGMKey = nil
	if clearDesired then
		desiredBGMKey = nil
	end
end

local function PlayBGM(bgmKey)
	if not bgmKey then
		return
	end

	desiredBGMKey = bgmKey

	if not soundSettings.MusicEnabled then
		DebugLog("Music disabled, skip BGM:", bgmKey)
		return
	end

	if currentBGMKey == bgmKey and currentBGM and currentBGM.IsPlaying then
		return
	end

	local newSound = GetOrCreateBGMSound(bgmKey)
	if not newSound then
		return
	end

	local config = SoundConfig.GetBGMConfig(bgmKey)
	local targetVolume = (config and config.Volume) or SoundConfig.Settings.BGMVolume
	local fadeDuration = SoundConfig.Settings.BGMFadeDuration or 0

	if currentBGM and currentBGM.IsPlaying then
		FadeOut(currentBGM, fadeDuration, function()
			FadeIn(newSound, targetVolume, fadeDuration)
		end)
	else
		FadeIn(newSound, targetVolume, fadeDuration)
	end

	currentBGM = newSound
	currentBGMKey = bgmKey
end

local function StopBGM()
	StopBGMInternal(true)
end

local function PlaySFX(sfxKey)
	if not soundSettings.SfxEnabled then
		DebugLog("SFX disabled, skip:", sfxKey)
		return
	end

	local sound = GetOrCreateSFXSound(sfxKey)
	if not sound then
		return
	end

	local config = SoundConfig.GetSFXConfig(sfxKey)
	sound.Volume = (config and config.Volume) or SoundConfig.Settings.SFXVolume

	if sound.IsPlaying then
		sound:Stop()
	end

	sound:Play()
	sfxInstances[sfxKey] = sound
end

local function StopSFX(sfxKey)
	local sound = sfxInstances[sfxKey]
	if sound and sound.IsPlaying then
		sound:Stop()
		DebugLog("Stop SFX:", sfxKey)
	end
end

local function ApplySoundSettings(musicEnabled, sfxEnabled)
	local previousMusic = soundSettings.MusicEnabled
	local previousSfx = soundSettings.SfxEnabled

	if type(musicEnabled) == "boolean" then
		soundSettings.MusicEnabled = musicEnabled
	end
	if type(sfxEnabled) == "boolean" then
		soundSettings.SfxEnabled = sfxEnabled
	end

	if previousMusic ~= soundSettings.MusicEnabled then
		if not soundSettings.MusicEnabled then
			if currentBGMKey and not desiredBGMKey then
				desiredBGMKey = currentBGMKey
			end
			StopBGMInternal(false)
		else
			if desiredBGMKey then
				PlayBGM(desiredBGMKey)
			end
		end
	end

	if previousSfx ~= soundSettings.SfxEnabled then
		if not soundSettings.SfxEnabled then
			StopAllSFX()
		end
	end
end

local function ConnectServerEvents()
	if eventsConnected then
		return true
	end

	local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
	if not eventsFolder then
		eventsFolder = ReplicatedStorage:WaitForChild("Events", 10)
	end
	if not eventsFolder then
		warn(LOG_PREFIX, "Events folder not found")
		return false
	end

	SoundEvents = eventsFolder:FindFirstChild("SoundEvents")
	if not SoundEvents then
		SoundEvents = eventsFolder:WaitForChild("SoundEvents", 10)
	end
	if not SoundEvents then
		warn(LOG_PREFIX, "SoundEvents folder not found")
		return false
	end

	local playBGMEvent = SoundEvents:FindFirstChild("PlayBGM")
	if playBGMEvent then
		playBGMEvent.OnClientEvent:Connect(function(bgmKey)
			PlayBGM(bgmKey)
		end)
	end

	local stopBGMEvent = SoundEvents:FindFirstChild("StopBGM")
	if stopBGMEvent then
		stopBGMEvent.OnClientEvent:Connect(function()
			StopBGM()
		end)
	end

	local playSFXEvent = SoundEvents:FindFirstChild("PlaySFX")
	if playSFXEvent then
		playSFXEvent.OnClientEvent:Connect(function(sfxKey)
			PlaySFX(sfxKey)
		end)
	end

	local stopSFXEvent = SoundEvents:FindFirstChild("StopSFX")
	if stopSFXEvent then
		stopSFXEvent.OnClientEvent:Connect(function(sfxKey)
			StopSFX(sfxKey)
		end)
	end

	local syncSettingsEvent = SoundEvents:FindFirstChild("SyncSoundSettings")
	if syncSettingsEvent then
		syncSettingsEvent.OnClientEvent:Connect(function(musicEnabled, sfxEnabled)
			ApplySoundSettings(musicEnabled, sfxEnabled)
		end)
	end

	eventsConnected = true
	return true
end

local function PreloadSounds()
	local assetsToPreload = {}

	for _, config in pairs(SoundConfig.BGM) do
		if config.SoundId then
			table.insert(assetsToPreload, config.SoundId)
		end
	end

	for _, config in pairs(SoundConfig.SFX) do
		if config.SoundId then
			table.insert(assetsToPreload, config.SoundId)
		end
	end

	if #assetsToPreload > 0 then
		task.spawn(function()
			pcall(function()
				ContentProvider:PreloadAsync(assetsToPreload)
			end)
			DebugLog("Preloaded sounds:", #assetsToPreload)
		end)
	end
end

local function Initialize()
	PreloadSounds()

	if not ConnectServerEvents() then
		warn(LOG_PREFIX, "Event connection failed, retrying...")
		task.delay(3, function()
			ConnectServerEvents()
		end)
	end

	isInitialized = true
end

local SoundController = {}

function SoundController.PlayBGM(bgmKey)
	PlayBGM(bgmKey)
end

function SoundController.StopBGM()
	StopBGM()
end

function SoundController.PlaySFX(sfxKey)
	PlaySFX(sfxKey)
end

function SoundController.StopSFX(sfxKey)
	StopSFX(sfxKey)
end

function SoundController.IsInitialized()
	return isInitialized
end

function SoundController.GetCurrentBGMKey()
	return currentBGMKey
end

function SoundController.GetSoundSettings()
	return {
		MusicEnabled = soundSettings.MusicEnabled,
		SfxEnabled = soundSettings.SfxEnabled,
	}
end

function SoundController.SetSoundSettings(musicEnabled, sfxEnabled)
	ApplySoundSettings(musicEnabled, sfxEnabled)
end

function SoundController.SetMusicEnabled(enabled)
	ApplySoundSettings(enabled, nil)
end

function SoundController.SetSfxEnabled(enabled)
	ApplySoundSettings(nil, enabled)
end

_G.SoundController = SoundController

Initialize()