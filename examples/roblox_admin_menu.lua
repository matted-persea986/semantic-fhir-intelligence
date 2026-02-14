--[[
Roblox Ultimate Admin Menu (Arabic)

مميزات متقدمة:
- واجهة حديثة + حواف RGB متحركة
- أزرار متطورة (Gradient + Hover Animation)
- قائمة لاعبين مباشرة داخل الماب
- نافذة المتبندين + فك باند مباشر
- نافذة المتبندين قابلة للسحب بالماوس
- لوحة الإدارة قابلة للسحب بالماوس
- إرسال رسالة أعلى الشاشة لكل اللاعبين
- تحذير لاعب محدد أو تحذير السيرفر كامل (ظهور واختفاء تدريجي)

الأوامر الأساسية:
Kick, Ban, Unban, ShowBanned, Kill, Pull, Freeze, Unfreeze, SetWalkSpeed, Broadcast

+ 10 خواص إدارية إضافية:
WarnPlayer, WarnServer, TopMessage, TeleportTo, BringAll, Heal, God, Ungod, Jail, Unjail, FreezeAll, UnfreezeAll

إضافات الإصدار الثاني:
Spectate, Unspectate, Invis, Reveal, Sparkles, Unsparkles, SetJumpPower

إضافات إضافية:
Respawn, ForceField, UnforceField, SetGravity, SetTime, Explode, Fire, Unfire

إضافة جديدة:
50 خاصية إدارة إضافية متنوعة (حرب/حركة/إضاءة/طقس/تحكم شامل)

إضافة أحدث:
تم توسيع الخصائص الإضافية إلى 100 + زر فتح للموبايل يظهر للأدمن فقط

التركيب:
1) داخل ReplicatedStorage أضف RemoteEvent باسم: AdminCommandEvent
2) أنشئ Script داخل ServerScriptService والصق قسم "Server Script".
3) أنشئ LocalScript داخل StarterPlayer > StarterPlayerScripts والصق قسم "Local Script".
4) عدّل ADMIN_USER_IDS و DISCORD_WEBHOOK_URL.
5) فعّل Http Requests من Game Settings > Security لاستخدام Webhook.
]]

--------------------------------------------------
-- Server Script (ServerScriptService)
--------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local DataStoreService = game:GetService("DataStoreService")
local Lighting = game:GetService("Lighting")

local ADMIN_USER_IDS = {
	[12345678] = true,
	[87654321] = true,
}

local DISCORD_WEBHOOK_URL = "PUT_YOUR_WEBHOOK_URL_HERE"
local BAN_STORE = DataStoreService:GetDataStore("AdminMenu_BanList_v3")
local BAN_INDEX_KEY = "BAN_INDEX"

local commandEvent = ReplicatedStorage:WaitForChild("AdminCommandEvent")
local godModeUsers = {}
local jailedUsers = {}
local invisibleUsers = {}

local function isAdmin(player)
	return ADMIN_USER_IDS[player.UserId] == true
end

local function findPlayerByName(name)
	if not name or name == "" then
		return nil
	end
	local lowered = string.lower(name)
	for _, p in ipairs(Players:GetPlayers()) do
		if string.lower(p.Name) == lowered or string.lower(p.DisplayName) == lowered then
			return p
		end
	end
	return nil
end

local function sendWebhook(adminPlayer, actionName, details)
	if DISCORD_WEBHOOK_URL == "" or DISCORD_WEBHOOK_URL == "PUT_YOUR_WEBHOOK_URL_HERE" then
		return
	end

	local payload = {
		username = "Roblox Admin Logs",
		embeds = {
			{
				title = "Admin Action: " .. actionName,
				color = 3447003,
				description = details,
				fields = {
					{ name = "Admin", value = string.format("%s (%d)", adminPlayer.Name, adminPlayer.UserId), inline = true },
					{ name = "Server JobId", value = game.JobId ~= "" and game.JobId or "Studio", inline = true },
				},
				timestamp = DateTime.now():ToIsoDate(),
			},
		},
	}

	task.spawn(function()
		pcall(function()
			HttpService:PostAsync(DISCORD_WEBHOOK_URL, HttpService:JSONEncode(payload), Enum.HttpContentType.ApplicationJson)
		end)
	end)
end

local function reply(player, message)
	commandEvent:FireClient(player, "SystemMessage", message)
end

local function getBanIndex()
	local ok, data = pcall(function()
		return BAN_STORE:GetAsync(BAN_INDEX_KEY)
	end)
	if not ok or type(data) ~= "table" then
		return {}
	end
	return data
end

local function saveBanIndex(index)
	pcall(function()
		BAN_STORE:SetAsync(BAN_INDEX_KEY, index)
	end)
end

local function addToBanIndex(userId)
	local index = getBanIndex()
	for _, id in ipairs(index) do
		if id == userId then
			return
		end
	end
	table.insert(index, userId)
	saveBanIndex(index)
end

local function removeFromBanIndex(userId)
	local index = getBanIndex()
	local newIndex = {}
	for _, id in ipairs(index) do
		if id ~= userId then
			table.insert(newIndex, id)
		end
	end
	saveBanIndex(newIndex)
end

local function setBannedRecord(userId, record)
	return pcall(function()
		BAN_STORE:SetAsync("BAN_" .. tostring(userId), record)
	end)
end

local function getBannedRecord(userId)
	local ok, result = pcall(function()
		return BAN_STORE:GetAsync("BAN_" .. tostring(userId))
	end)
	if not ok then
		return nil
	end
	return result
end

local function clearBan(userId)
	local ok = pcall(function()
		BAN_STORE:RemoveAsync("BAN_" .. tostring(userId))
	end)
	if ok then
		removeFromBanIndex(userId)
	end
	return ok
end

local function getHumanoid(player)
	if not player or not player.Character then
		return nil
	end
	return player.Character:FindFirstChildOfClass("Humanoid")
end

local function getRoot(player)
	if not player or not player.Character then
		return nil
	end
	return player.Character:FindFirstChild("HumanoidRootPart")
end

local function getBannedList()
	local list = {}
	for _, userId in ipairs(getBanIndex()) do
		local rec = getBannedRecord(userId)
		if rec then
			table.insert(list, {
				userId = rec.userId or userId,
				playerName = rec.playerName or "Unknown",
				reason = rec.reason or "No reason",
				adminName = rec.adminName or "Unknown",
				adminUserId = rec.adminUserId or 0,
				bannedAt = rec.bannedAt or 0,
			})
		end
	end
	return list
end

Players.PlayerAdded:Connect(function(player)
	local record = getBannedRecord(player.UserId)
	if record then
		player:Kick("You are banned from this game. Reason: " .. tostring(record.reason or "Banned"))
		return
	end

	player.CharacterAdded:Connect(function(character)
		task.wait(0.2)
		if godModeUsers[player.UserId] then
			local hum = character:FindFirstChildOfClass("Humanoid")
			if hum then
				hum.MaxHealth = 1e9
				hum.Health = hum.MaxHealth
			end
		end
		if jailedUsers[player.UserId] then
			local root = character:FindFirstChild("HumanoidRootPart")
			if root then
				root.CFrame = jailedUsers[player.UserId]
			end
		end
		if invisibleUsers[player.UserId] then
			for _, obj in ipairs(character:GetDescendants()) do
				if obj:IsA("BasePart") then
					obj.Transparency = 1
				elseif obj:IsA("Decal") then
					obj.Transparency = 1
				end
			end
		end
	end)
end)

local function actionKick(admin, targetName, reason)
	local target = findPlayerByName(targetName)
	if not target then return false, "لم يتم العثور على اللاعب" end
	target:Kick(reason ~= "" and reason or "Kicked by admin")
	sendWebhook(admin, "Kick", target.Name)
	return true, "تم طرد " .. target.Name
end

local function actionBan(admin, targetName, reason)
	local target = findPlayerByName(targetName)
	if not target then return false, "لم يتم العثور على اللاعب" end
	local record = {
		userId = target.UserId,
		playerName = target.Name,
		reason = reason ~= "" and reason or "Banned by admin",
		adminName = admin.Name,
		adminUserId = admin.UserId,
		bannedAt = os.time(),
	}
	if not setBannedRecord(target.UserId, record) then
		return false, "فشل حفظ الباند"
	end
	addToBanIndex(target.UserId)
	target:Kick(record.reason)
	sendWebhook(admin, "Ban", target.Name)
	return true, "تم تبنيد " .. target.Name
end

local function actionUnban(admin, userIdText)
	local userId = tonumber(userIdText)
	if not userId then return false, "اكتب UserId صحيح" end
	if not getBannedRecord(userId) then return false, "غير مبند" end
	if not clearBan(userId) then return false, "فشل فك الباند" end
	sendWebhook(admin, "Unban", tostring(userId))
	return true, "تم فك الباند"
end

local function actionKill(admin, targetName)
	local target = findPlayerByName(targetName)
	local hum = getHumanoid(target)
	if not hum then return false, "تعذر قتل اللاعب" end
	hum.Health = 0
	sendWebhook(admin, "Kill", target.Name)
	return true, "تم قتل " .. target.Name
end

local function actionPull(admin, targetName)
	local target = findPlayerByName(targetName)
	local tRoot, aRoot = getRoot(target), getRoot(admin)
	if not tRoot or not aRoot then return false, "تعذر السحب" end
	tRoot.CFrame = aRoot.CFrame * CFrame.new(2, 0, 0)
	sendWebhook(admin, "Pull", target.Name)
	return true, "تم سحب " .. target.Name
end

local function actionFreeze(admin, targetName, state)
	local target = findPlayerByName(targetName)
	local root = getRoot(target)
	if not root then return false, "تعذر التثبيت" end
	root.Anchored = state
	sendWebhook(admin, state and "Freeze" or "Unfreeze", target.Name)
	return true, state and "تم التثبيت" or "تم فك التثبيت"
end

local function actionSetSpeed(admin, targetName, speed)
	local target = findPlayerByName(targetName)
	local hum = getHumanoid(target)
	if not hum then return false, "تعذر تعديل السرعة" end
	hum.WalkSpeed = math.clamp(speed, 0, 250)
	sendWebhook(admin, "SetSpeed", target.Name .. " = " .. tostring(speed))
	return true, "تم تعديل السرعة"
end

local function actionBroadcast(admin, message)
	if message == "" then return false, "اكتب رسالة" end
	for _, p in ipairs(Players:GetPlayers()) do
		commandEvent:FireClient(p, "BroadcastMessage", message)
	end
	sendWebhook(admin, "Broadcast", message)
	return true, "تم الإرسال"
end

local function actionTopMessage(admin, message)
	if message == "" then return false, "اكتب رسالة أعلى الشاشة" end
	for _, p in ipairs(Players:GetPlayers()) do
		commandEvent:FireClient(p, "TopMessage", message)
	end
	local hint = Instance.new("Hint")
	hint.Text = message
	hint.Parent = workspace
	task.delay(5, function() if hint then hint:Destroy() end end)
	sendWebhook(admin, "TopMessage", message)
	return true, "تم عرض الرسالة أعلى الشاشة"
end

local function actionWarnPlayer(admin, targetName, warningText)
	local target = findPlayerByName(targetName)
	if not target then return false, "اللاعب غير موجود" end
	if warningText == "" then return false, "اكتب نص التحذير" end
	commandEvent:FireClient(target, "WarningMessage", "تحذير من الإدارة: " .. warningText)
	sendWebhook(admin, "WarnPlayer", target.Name .. " => " .. warningText)
	return true, "تم تحذير " .. target.Name
end

local function actionWarnServer(admin, warningText)
	if warningText == "" then return false, "اكتب نص التحذير" end
	for _, p in ipairs(Players:GetPlayers()) do
		commandEvent:FireClient(p, "WarningMessage", "تحذير عام: " .. warningText)
	end
	sendWebhook(admin, "WarnServer", warningText)
	return true, "تم إرسال تحذير عام"
end

local function actionTeleportTo(admin, targetName)
	local target = findPlayerByName(targetName)
	local aRoot, tRoot = getRoot(admin), getRoot(target)
	if not aRoot or not tRoot then return false, "تعذر الانتقال" end
	aRoot.CFrame = tRoot.CFrame * CFrame.new(2, 0, 0)
	sendWebhook(admin, "TeleportTo", target.Name)
	return true, "تم الانتقال إلى " .. target.Name
end

local function actionBringAll(admin)
	local aRoot = getRoot(admin)
	if not aRoot then return false, "تعذر تنفيذ BringAll" end
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= admin then
			local root = getRoot(p)
			if root then
				root.CFrame = aRoot.CFrame * CFrame.new(math.random(-6, 6), 0, math.random(-6, 6))
			end
		end
	end
	sendWebhook(admin, "BringAll", "all players")
	return true, "تم سحب كل اللاعبين إليك"
end

local function actionHeal(admin, targetName)
	local target = findPlayerByName(targetName)
	local hum = getHumanoid(target)
	if not hum then return false, "تعذر العلاج" end
	hum.Health = hum.MaxHealth
	sendWebhook(admin, "Heal", target.Name)
	return true, "تم علاج " .. target.Name
end

local function actionGod(admin, targetName)
	local target = findPlayerByName(targetName)
	local hum = getHumanoid(target)
	if not hum then return false, "تعذر تفعيل God" end
	godModeUsers[target.UserId] = true
	hum.MaxHealth = 1e9
	hum.Health = hum.MaxHealth
	sendWebhook(admin, "God", target.Name)
	return true, "تم تفعيل God"
end

local function actionUngod(admin, targetName)
	local target = findPlayerByName(targetName)
	local hum = getHumanoid(target)
	if not hum then return false, "تعذر إلغاء God" end
	godModeUsers[target.UserId] = nil
	hum.MaxHealth = 100
	hum.Health = math.min(hum.Health, 100)
	sendWebhook(admin, "Ungod", target.Name)
	return true, "تم إلغاء God"
end

local function actionJail(admin, targetName)
	local target = findPlayerByName(targetName)
	local root = getRoot(target)
	if not root then return false, "تعذر السجن" end
	local jailPos = CFrame.new(0, 10, 0)
	jailedUsers[target.UserId] = jailPos
	root.CFrame = jailPos
	root.Anchored = true
	sendWebhook(admin, "Jail", target.Name)
	return true, "تم سجن " .. target.Name
end

local function actionUnjail(admin, targetName)
	local target = findPlayerByName(targetName)
	local root = getRoot(target)
	if not root then return false, "تعذر فك السجن" end
	jailedUsers[target.UserId] = nil
	root.Anchored = false
	sendWebhook(admin, "Unjail", target.Name)
	return true, "تم فك السجن"
end

local function actionFreezeAll(admin, state)
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= admin then
			local root = getRoot(p)
			if root then root.Anchored = state end
		end
	end
	sendWebhook(admin, state and "FreezeAll" or "UnfreezeAll", "all")
	return true, state and "تم تثبيت الجميع" or "تم فك تثبيت الجميع"
end

local function actionSetJumpPower(admin, targetName, jumpPower)
	local target = findPlayerByName(targetName)
	local hum = getHumanoid(target)
	if not hum then return false, "تعذر تعديل القفز" end
	hum.JumpPower = math.clamp(jumpPower, 0, 250)
	sendWebhook(admin, "SetJumpPower", target.Name .. " = " .. tostring(jumpPower))
	return true, "تم تعديل القفز"
end

local function actionInvis(admin, targetName, state)
	local target = findPlayerByName(targetName)
	if not target or not target.Character then
		return false, "تعذر تغيير حالة الإخفاء"
	end
	for _, obj in ipairs(target.Character:GetDescendants()) do
		if obj:IsA("BasePart") then
			obj.Transparency = state and 1 or 0
		elseif obj:IsA("Decal") then
			obj.Transparency = state and 1 or 0
		end
	end
	invisibleUsers[target.UserId] = state and true or nil
	sendWebhook(admin, state and "Invis" or "Reveal", target.Name)
	return true, state and "تم إخفاء اللاعب" or "تم إظهار اللاعب"
end

local function actionSparkles(admin, targetName, state)
	local target = findPlayerByName(targetName)
	local root = getRoot(target)
	if not root then return false, "تعذر تعديل Sparkles" end
	local current = root:FindFirstChild("AdminSparkles")
	if state then
		if not current then
			local spark = Instance.new("Sparkles")
			spark.Name = "AdminSparkles"
			spark.SparkleColor = Color3.fromRGB(95, 175, 255)
			spark.Parent = root
		end
	else
		if current then current:Destroy() end
	end
	sendWebhook(admin, state and "Sparkles" or "Unsparkles", target.Name)
	return true, state and "تم تفعيل اللمعة" or "تم إيقاف اللمعة"
end

local function actionRespawn(admin, targetName)
	local target = findPlayerByName(targetName)
	if not target then return false, "اللاعب غير موجود" end
	target:LoadCharacter()
	sendWebhook(admin, "Respawn", target.Name)
	return true, "تم إعادة إحياء " .. target.Name
end

local function actionForceField(admin, targetName, state)
	local target = findPlayerByName(targetName)
	if not target or not target.Character then return false, "تعذر تعديل ForceField" end
	local ff = target.Character:FindFirstChild("AdminForceField")
	if state then
		if not ff then
			ff = Instance.new("ForceField")
			ff.Name = "AdminForceField"
			ff.Visible = true
			ff.Parent = target.Character
		end
	else
		if ff then ff:Destroy() end
	end
	sendWebhook(admin, state and "ForceField" or "UnforceField", target.Name)
	return true, state and "تم تفعيل الدرع" or "تم إلغاء الدرع"
end

local function actionSetGravity(admin, value)
	local gravity = math.clamp(value, 0, 300)
	workspace.Gravity = gravity
	sendWebhook(admin, "SetGravity", tostring(gravity))
	return true, "تم ضبط الجاذبية على " .. tostring(gravity)
end

local function actionSetTime(admin, timeText)
	if timeText == "" then return false, "اكتب الوقت مثل 14:30" end
	Lighting.ClockTime = tonumber(timeText) or Lighting.ClockTime
	if tonumber(timeText) == nil then
		Lighting.TimeOfDay = timeText
	end
	sendWebhook(admin, "SetTime", tostring(timeText))
	return true, "تم تعديل وقت السيرفر"
end

local function actionExplode(admin, targetName)
	local target = findPlayerByName(targetName)
	local root = getRoot(target)
	if not root then return false, "تعذر التفجير" end
	local ex = Instance.new("Explosion")
	ex.Position = root.Position
	ex.BlastRadius = 8
	ex.BlastPressure = 500000
	ex.DestroyJointRadiusPercent = 0
	ex.Parent = workspace
	sendWebhook(admin, "Explode", target.Name)
	return true, "تم تفجير " .. target.Name
end

local function actionFireEffect(admin, targetName, state)
	local target = findPlayerByName(targetName)
	local root = getRoot(target)
	if not root then return false, "تعذر تعديل تأثير النار" end
	local fx = root:FindFirstChild("AdminFire")
	if state then
		if not fx then
			fx = Instance.new("Fire")
			fx.Name = "AdminFire"
			fx.Color = Color3.fromRGB(255, 170, 70)
			fx.SecondaryColor = Color3.fromRGB(255, 70, 40)
			fx.Heat = 8
			fx.Size = 7
			fx.Parent = root
		end
	else
		if fx then fx:Destroy() end
	end
	sendWebhook(admin, state and "Fire" or "Unfire", target.Name)
	return true, state and "تم تفعيل النار" or "تم إيقاف النار"
end

-- 50 مزايا إضافية للإدارة
local stunStates = {}

local function forAllPlayers(fn)
	for _, p in ipairs(Players:GetPlayers()) do
		fn(p)
	end
end

local function actionSetHumValue(admin, targetName, key, value)
	local target = findPlayerByName(targetName)
	local hum = getHumanoid(target)
	if not hum then return false, "اللاعب غير موجود" end
	if key == "Health" then hum.Health = math.clamp(value, 0, hum.MaxHealth)
	elseif key == "MaxHealth" then hum.MaxHealth = math.clamp(value, 1, 1e9); hum.Health = math.min(hum.Health, hum.MaxHealth)
	elseif key == "WalkSpeed" then hum.WalkSpeed = math.clamp(value, 0, 250)
	elseif key == "JumpPower" then hum.JumpPower = math.clamp(value, 0, 250)
	end
	return true, "تم التنفيذ"
end

local function actionScaleMode(targetName, mode)
	local target = findPlayerByName(targetName)
	local hum = getHumanoid(target)
	if not hum then return false, "اللاعب غير موجود" end
	local v = (mode == "tiny" and 0.6) or (mode == "big" and 1.35) or 1
	pcall(function()
		hum.BodyHeightScale.Value = v
		hum.BodyWidthScale.Value = v
		hum.BodyDepthScale.Value = v
		hum.HeadScale.Value = v
	end)
	return true, "تم تعديل الحجم"
end

local extraCommandHandlers = {
	SetHealth = function(admin, payload) return actionSetHumValue(admin, payload.targetName or "", "Health", tonumber(payload.value) or 100) end,
	SetMaxHealth = function(admin, payload) return actionSetHumValue(admin, payload.targetName or "", "MaxHealth", tonumber(payload.value) or 100) end,
	Damage = function(admin, payload) return actionSetHumValue(admin, payload.targetName or "", "Health", 0) end,
	DamageAll = function(admin)
		forAllPlayers(function(p) local h=getHumanoid(p) if h then h.Health = math.max(0, h.Health - 35) end end)
		return true, "تم ضرر الجميع"
	end,
	HealAll = function(admin)
		forAllPlayers(function(p) local h=getHumanoid(p) if h then h.Health = h.MaxHealth end end)
		return true, "تم علاج الجميع"
	end,
	Slow = function(admin, payload) return actionSetHumValue(admin, payload.targetName or "", "WalkSpeed", 8) end,
	Fast = function(admin, payload) return actionSetHumValue(admin, payload.targetName or "", "WalkSpeed", 32) end,
	ResetSpeed = function(admin, payload) return actionSetHumValue(admin, payload.targetName or "", "WalkSpeed", 16) end,
	JumpBoost = function(admin, payload) return actionSetHumValue(admin, payload.targetName or "", "JumpPower", 90) end,
	ResetJump = function(admin, payload) return actionSetHumValue(admin, payload.targetName or "", "JumpPower", 50) end,
	Sit = function(admin, payload)
		local h=getHumanoid(findPlayerByName(payload.targetName or "")); if not h then return false, "اللاعب غير موجود" end; h.Sit=true; return true, "تم إجلاس اللاعب"
	end,
	Unsit = function(admin, payload)
		local h=getHumanoid(findPlayerByName(payload.targetName or "")); if not h then return false, "اللاعب غير موجود" end; h.Sit=false; return true, "تم إلغاء الجلوس"
	end,
	Tiny = function(admin, payload) return actionScaleMode(payload.targetName or "", "tiny") end,
	Big = function(admin, payload) return actionScaleMode(payload.targetName or "", "big") end,
	NormalSize = function(admin, payload) return actionScaleMode(payload.targetName or "", "normal") end,
	Noclip = function(admin, payload)
		local t=findPlayerByName(payload.targetName or ""); if not t or not t.Character then return false, "اللاعب غير موجود" end
		for _,d in ipairs(t.Character:GetDescendants()) do if d:IsA("BasePart") then d.CanCollide=false end end
		return true, "تم تفعيل Noclip"
	end,
	Clip = function(admin, payload)
		local t=findPlayerByName(payload.targetName or ""); if not t or not t.Character then return false, "اللاعب غير موجود" end
		for _,d in ipairs(t.Character:GetDescendants()) do if d:IsA("BasePart") then d.CanCollide=true end end
		return true, "تم إلغاء Noclip"
	end,
	Spin = function(admin, payload)
		local r=getRoot(findPlayerByName(payload.targetName or "")); if not r then return false, "اللاعب غير موجود" end
		r.AssemblyAngularVelocity = Vector3.new(0, 28, 0); return true, "تم التدوير"
	end,
	Unspin = function(admin, payload)
		local r=getRoot(findPlayerByName(payload.targetName or "")); if not r then return false, "اللاعب غير موجود" end
		r.AssemblyAngularVelocity = Vector3.new(0, 0, 0); return true, "تم إيقاف التدوير"
	end,
	Fling = function(admin, payload)
		local r=getRoot(findPlayerByName(payload.targetName or "")); if not r then return false, "اللاعب غير موجود" end
		r.AssemblyLinearVelocity = Vector3.new(math.random(-160,160), 140, math.random(-160,160)); return true, "تم Fling"
	end,
	Trip = function(admin, payload)
		local h=getHumanoid(findPlayerByName(payload.targetName or "")); if not h then return false, "اللاعب غير موجود" end
		h.PlatformStand = true; task.delay(1.5, function() if h then h.PlatformStand = false end end); return true, "تم إسقاط اللاعب"
	end,
	Stun = function(admin, payload)
		local t=findPlayerByName(payload.targetName or ""); local h=getHumanoid(t); if not h then return false, "اللاعب غير موجود" end
		stunStates[t.UserId] = {w=h.WalkSpeed,j=h.JumpPower}; h.WalkSpeed=0; h.JumpPower=0; return true, "تم Stun"
	end,
	Unstun = function(admin, payload)
		local t=findPlayerByName(payload.targetName or ""); local h=getHumanoid(t); if not h then return false, "اللاعب غير موجود" end
		local s=stunStates[t.UserId]; h.WalkSpeed=(s and s.w) or 16; h.JumpPower=(s and s.j) or 50; stunStates[t.UserId]=nil; return true, "تم فك Stun"
	end,
	Launch = function(admin, payload)
		local r=getRoot(findPlayerByName(payload.targetName or "")); if not r then return false, "اللاعب غير موجود" end
		r.AssemblyLinearVelocity = Vector3.new(0, 170, 0); return true, "تم الإطلاق"
	end,
	Shockwave = function(admin, payload)
		local r=getRoot(findPlayerByName(payload.targetName or "")); if not r then return false, "اللاعب غير موجود" end
		local e=Instance.new("Explosion"); e.Position=r.Position; e.BlastRadius=12; e.BlastPressure=450000; e.DestroyJointRadiusPercent=0; e.Parent=workspace; return true, "تم Shockwave"
	end,
	RespawnAll = function(admin)
		forAllPlayers(function(p) p:LoadCharacter() end); return true, "تم Respawn للجميع"
	end,
	KickAll = function(admin)
		forAllPlayers(function(p) if p~=admin then p:Kick("KickAll by admin") end end); return true, "تم KickAll"
	end,
	GodAll = function(admin)
		forAllPlayers(function(p) local h=getHumanoid(p) if h then h.MaxHealth=1e9; h.Health=h.MaxHealth; godModeUsers[p.UserId]=true end end); return true, "تم GodAll"
	end,
	UngodAll = function(admin)
		forAllPlayers(function(p) local h=getHumanoid(p) if h then h.MaxHealth=100; h.Health=math.min(h.Health,100); godModeUsers[p.UserId]=nil end end); return true, "تم UngodAll"
	end,
	SparklesAll = function(admin)
		forAllPlayers(function(p) local r=getRoot(p); if r and not r:FindFirstChild("AdminSparkles") then local s=Instance.new("Sparkles"); s.Name="AdminSparkles"; s.Parent=r end end); return true, "تم SparklesAll"
	end,
	UnsparklesAll = function(admin)
		forAllPlayers(function(p) local r=getRoot(p); if r and r:FindFirstChild("AdminSparkles") then r.AdminSparkles:Destroy() end end); return true, "تم UnsparklesAll"
	end,
	FireAll = function(admin)
		forAllPlayers(function(p) local r=getRoot(p); if r and not r:FindFirstChild("AdminFire") then local f=Instance.new("Fire"); f.Name="AdminFire"; f.Parent=r end end); return true, "تم FireAll"
	end,
	UnfireAll = function(admin)
		forAllPlayers(function(p) local r=getRoot(p); if r and r:FindFirstChild("AdminFire") then r.AdminFire:Destroy() end end); return true, "تم UnfireAll"
	end,
	InvisAll = function(admin)
		forAllPlayers(function(p) if p.Character then for _,d in ipairs(p.Character:GetDescendants()) do if d:IsA("BasePart") or d:IsA("Decal") then d.Transparency=1 end end end end); return true, "تم InvisAll"
	end,
	RevealAll = function(admin)
		forAllPlayers(function(p) if p.Character then for _,d in ipairs(p.Character:GetDescendants()) do if d:IsA("BasePart") or d:IsA("Decal") then d.Transparency=0 end end end end); return true, "تم RevealAll"
	end,
	GravityLow = function(admin) workspace.Gravity = 80; return true, "تم Low Gravity" end,
	GravityNormal = function(admin) workspace.Gravity = 196.2; return true, "تم Normal Gravity" end,
	GravityHigh = function(admin) workspace.Gravity = 260; return true, "تم High Gravity" end,
	TimeDay = function(admin) Lighting.ClockTime = 9; return true, "تم Day" end,
	TimeNight = function(admin) Lighting.ClockTime = 22; return true, "تم Night" end,
	TimeNoon = function(admin) Lighting.ClockTime = 12; return true, "تم Noon" end,
	TimeMidnight = function(admin) Lighting.ClockTime = 0; return true, "تم Midnight" end,
	FogOn = function(admin) Lighting.FogEnd = 120; Lighting.FogStart = 0; return true, "تم Fog On" end,
	FogOff = function(admin) Lighting.FogEnd = 100000; Lighting.FogStart = 0; return true, "تم Fog Off" end,
	BrightLow = function(admin) Lighting.Brightness = 1; return true, "إضاءة منخفضة" end,
	BrightNormal = function(admin) Lighting.Brightness = 2; return true, "إضاءة طبيعية" end,
	BrightHigh = function(admin) Lighting.Brightness = 4; return true, "إضاءة عالية" end,
	LockMap = function(admin)
		for _,obj in ipairs(workspace:GetDescendants()) do if obj:IsA("BasePart") and not obj:IsDescendantOf(workspace.CurrentCamera) then obj.Anchored = true end end
		return true, "تم قفل الماب"
	end,
	UnlockMap = function(admin)
		for _,obj in ipairs(workspace:GetDescendants()) do if obj:IsA("BasePart") then obj.Anchored = false end end
		return true, "تم فتح الماب"
	end,
	KillAll = function(admin)
		forAllPlayers(function(p) local h=getHumanoid(p) if h then h.Health = 0 end end)
		return true, "تم KillAll"
	end,
	HP25 = function(admin,payload) return actionSetHumValue(admin, payload.targetName or "", "Health", 25) end,
	HP50 = function(admin,payload) return actionSetHumValue(admin, payload.targetName or "", "Health", 50) end,
	HP75 = function(admin,payload) return actionSetHumValue(admin, payload.targetName or "", "Health", 75) end,
	HP100 = function(admin,payload) return actionSetHumValue(admin, payload.targetName or "", "Health", 100) end,
	HP200 = function(admin,payload) return actionSetHumValue(admin, payload.targetName or "", "Health", 200) end,
	Damage5 = function(admin,payload) local t=findPlayerByName(payload.targetName or ""); local h=getHumanoid(t); if not h then return false,"اللاعب غير موجود" end; h.Health=math.max(0,h.Health-5); return true,"تم Damage5" end,
	Damage15 = function(admin,payload) local t=findPlayerByName(payload.targetName or ""); local h=getHumanoid(t); if not h then return false,"اللاعب غير موجود" end; h.Health=math.max(0,h.Health-15); return true,"تم Damage15" end,
	Damage30 = function(admin,payload) local t=findPlayerByName(payload.targetName or ""); local h=getHumanoid(t); if not h then return false,"اللاعب غير موجود" end; h.Health=math.max(0,h.Health-30); return true,"تم Damage30" end,
	Damage60 = function(admin,payload) local t=findPlayerByName(payload.targetName or ""); local h=getHumanoid(t); if not h then return false,"اللاعب غير موجود" end; h.Health=math.max(0,h.Health-60); return true,"تم Damage60" end,
	Damage95 = function(admin,payload) local t=findPlayerByName(payload.targetName or ""); local h=getHumanoid(t); if not h then return false,"اللاعب غير موجود" end; h.Health=math.max(0,h.Health-95); return true,"تم Damage95" end,
	Speed12 = function(admin,payload) return actionSetHumValue(admin, payload.targetName or "", "WalkSpeed", 12) end,
	Speed24 = function(admin,payload) return actionSetHumValue(admin, payload.targetName or "", "WalkSpeed", 24) end,
	Speed48 = function(admin,payload) return actionSetHumValue(admin, payload.targetName or "", "WalkSpeed", 48) end,
	Speed64 = function(admin,payload) return actionSetHumValue(admin, payload.targetName or "", "WalkSpeed", 64) end,
	Speed96 = function(admin,payload) return actionSetHumValue(admin, payload.targetName or "", "WalkSpeed", 96) end,
	Jump30 = function(admin,payload) return actionSetHumValue(admin, payload.targetName or "", "JumpPower", 30) end,
	Jump60 = function(admin,payload) return actionSetHumValue(admin, payload.targetName or "", "JumpPower", 60) end,
	Jump100 = function(admin,payload) return actionSetHumValue(admin, payload.targetName or "", "JumpPower", 100) end,
	Jump140 = function(admin,payload) return actionSetHumValue(admin, payload.targetName or "", "JumpPower", 140) end,
	Jump200 = function(admin,payload) return actionSetHumValue(admin, payload.targetName or "", "JumpPower", 200) end,
	Gravity40 = function() workspace.Gravity=40; return true,"Gravity40" end,
	Gravity70 = function() workspace.Gravity=70; return true,"Gravity70" end,
	Gravity110 = function() workspace.Gravity=110; return true,"Gravity110" end,
	Gravity150 = function() workspace.Gravity=150; return true,"Gravity150" end,
	Gravity210 = function() workspace.Gravity=210; return true,"Gravity210" end,
	TimeSunrise = function() Lighting.ClockTime=6; return true,"Sunrise" end,
	TimeMorning = function() Lighting.ClockTime=9; return true,"Morning" end,
	TimeEvening = function() Lighting.ClockTime=17; return true,"Evening" end,
	TimeLateNight = function() Lighting.ClockTime=23; return true,"LateNight" end,
	TimeDawn = function() Lighting.ClockTime=4; return true,"Dawn" end,
	FreezeEveryone = function(admin) return actionFreezeAll(admin,true) end,
	UnfreezeEveryone = function(admin) return actionFreezeAll(admin,false) end,
	PullEveryone = function(admin) return actionBringAll(admin) end,
	BringRandom = function(admin)
		local list=Players:GetPlayers(); if #list==0 then return false,"لا يوجد لاعبين" end; local p=list[math.random(1,#list)]; return actionPull(admin,p.Name)
	end,
	ScatterAll = function(admin)
		forAllPlayers(function(p) local r=getRoot(p); if r then r.CFrame = CFrame.new(math.random(-120,120), math.random(8,30), math.random(-120,120)) end end)
		return true,"تم ScatterAll"
	end,
	SparklesRainbow = function()
		forAllPlayers(function(p) local r=getRoot(p); if r then local s=r:FindFirstChild("AdminSparkles") or Instance.new("Sparkles",r); s.Name="AdminSparkles"; s.SparkleColor=Color3.fromHSV(math.random(),1,1) end end); return true,"SparklesRainbow"
	end,
	FireGreen = function()
		forAllPlayers(function(p) local r=getRoot(p); if r then local f=r:FindFirstChild("AdminFire") or Instance.new("Fire",r); f.Name="AdminFire"; f.Color=Color3.fromRGB(80,255,120); f.SecondaryColor=Color3.fromRGB(20,200,70) end end); return true,"FireGreen"
	end,
	Confetti = function()
		forAllPlayers(function(p) commandEvent:FireClient(p, "TopMessage", "🎉 Confetti Time!") end); return true,"Confetti"
	end,
	SmokeOn = function()
		forAllPlayers(function(p) local r=getRoot(p); if r and not r:FindFirstChild("AdminSmoke") then local s=Instance.new("Smoke"); s.Name="AdminSmoke"; s.Parent=r end end); return true,"SmokeOn"
	end,
	SmokeOff = function()
		forAllPlayers(function(p) local r=getRoot(p); if r and r:FindFirstChild("AdminSmoke") then r.AdminSmoke:Destroy() end end); return true,"SmokeOff"
	end,
	BlindAll = function()
		forAllPlayers(function(p) commandEvent:FireClient(p, "TopMessage", "⚫ تم تعتيم الشاشة") end); Lighting.Brightness = 0; return true,"BlindAll"
	end,
	UnblindAll = function()
		Lighting.Brightness = 2; return true,"UnblindAll"
	end,
	LowHealthAll = function()
		forAllPlayers(function(p) local h=getHumanoid(p); if h then h.Health = math.min(h.Health, 10) end end); return true,"LowHealthAll"
	end,
	MaxHealthAll = function()
		forAllPlayers(function(p) local h=getHumanoid(p); if h then h.MaxHealth=500; h.Health=500 end end); return true,"MaxHealthAll"
	end,
	ResetAllStats = function()
		forAllPlayers(function(p) local h=getHumanoid(p); if h then h.WalkSpeed=16; h.JumpPower=50; h.MaxHealth=100; h.Health=100 end end); return true,"ResetAllStats"
	end,
	BounceAll = function()
		forAllPlayers(function(p) local r=getRoot(p); if r then r.AssemblyLinearVelocity = Vector3.new(0,120,0) end end); return true,"BounceAll"
	end,
	StopAllVelocity = function()
		forAllPlayers(function(p) local r=getRoot(p); if r then r.AssemblyLinearVelocity=Vector3.new(); r.AssemblyAngularVelocity=Vector3.new() end end); return true,"StopAllVelocity"
	end,
	AnchorAll = function()
		forAllPlayers(function(p) local r=getRoot(p); if r then r.Anchored=true end end); return true,"AnchorAll"
	end,
	UnanchorAll = function()
		forAllPlayers(function(p) local r=getRoot(p); if r then r.Anchored=false end end); return true,"UnanchorAll"
	end,
	CleanMapEffects = function()
		for _,obj in ipairs(workspace:GetDescendants()) do if obj.Name=="AdminFire" or obj.Name=="AdminSparkles" or obj.Name=="AdminSmoke" then obj:Destroy() end end
		return true,"CleanMapEffects"
	end,
	}

commandEvent.OnServerEvent:Connect(function(player, action, payload)
	if not isAdmin(player) then
		reply(player, "غير مصرح لك")
		return
	end
	payload = payload or {}
	local ok, msg = false, "أمر غير معروف"

	if action == "Kick" then ok, msg = actionKick(player, payload.targetName or "", payload.reason or "")
	elseif action == "Ban" then ok, msg = actionBan(player, payload.targetName or "", payload.reason or "")
	elseif action == "Unban" then ok, msg = actionUnban(player, payload.userId or "")
	elseif action == "ShowBanned" then commandEvent:FireClient(player, "BannedList", getBannedList()); ok, msg = true, "تم جلب المتبندين"
	elseif action == "Kill" then ok, msg = actionKill(player, payload.targetName or "")
	elseif action == "Pull" then ok, msg = actionPull(player, payload.targetName or "")
	elseif action == "Freeze" then ok, msg = actionFreeze(player, payload.targetName or "", true)
	elseif action == "Unfreeze" then ok, msg = actionFreeze(player, payload.targetName or "", false)
	elseif action == "SetWalkSpeed" then ok, msg = actionSetSpeed(player, payload.targetName or "", tonumber(payload.speed) or 16)
	elseif action == "Broadcast" then ok, msg = actionBroadcast(player, payload.message or "")
	elseif action == "TopMessage" then ok, msg = actionTopMessage(player, payload.message or "")
	elseif action == "WarnPlayer" then ok, msg = actionWarnPlayer(player, payload.targetName or "", payload.message or "")
	elseif action == "WarnServer" then ok, msg = actionWarnServer(player, payload.message or "")
	elseif action == "TeleportTo" then ok, msg = actionTeleportTo(player, payload.targetName or "")
	elseif action == "BringAll" then ok, msg = actionBringAll(player)
	elseif action == "Heal" then ok, msg = actionHeal(player, payload.targetName or "")
	elseif action == "God" then ok, msg = actionGod(player, payload.targetName or "")
	elseif action == "Ungod" then ok, msg = actionUngod(player, payload.targetName or "")
	elseif action == "Jail" then ok, msg = actionJail(player, payload.targetName or "")
	elseif action == "Unjail" then ok, msg = actionUnjail(player, payload.targetName or "")
	elseif action == "FreezeAll" then ok, msg = actionFreezeAll(player, true)
	elseif action == "UnfreezeAll" then ok, msg = actionFreezeAll(player, false)
	elseif action == "SetJumpPower" then ok, msg = actionSetJumpPower(player, payload.targetName or "", tonumber(payload.jumpPower) or 50)
	elseif action == "Invis" then ok, msg = actionInvis(player, payload.targetName or "", true)
	elseif action == "Reveal" then ok, msg = actionInvis(player, payload.targetName or "", false)
	elseif action == "Sparkles" then ok, msg = actionSparkles(player, payload.targetName or "", true)
	elseif action == "Unsparkles" then ok, msg = actionSparkles(player, payload.targetName or "", false)
	elseif action == "Spectate" then commandEvent:FireClient(player, "SpectateStart", payload.targetName or ""); ok, msg = true, "تم بدء المشاهدة"
	elseif action == "Unspectate" then commandEvent:FireClient(player, "SpectateStop"); ok, msg = true, "تم إيقاف المشاهدة"
	elseif action == "Respawn" then ok, msg = actionRespawn(player, payload.targetName or "")
	elseif action == "ForceField" then ok, msg = actionForceField(player, payload.targetName or "", true)
	elseif action == "UnforceField" then ok, msg = actionForceField(player, payload.targetName or "", false)
	elseif action == "SetGravity" then ok, msg = actionSetGravity(player, tonumber(payload.value) or 196)
	elseif action == "SetTime" then ok, msg = actionSetTime(player, payload.value or "")
	elseif action == "Explode" then ok, msg = actionExplode(player, payload.targetName or "")
	elseif action == "Fire" then ok, msg = actionFireEffect(player, payload.targetName or "", true)
	elseif action == "Unfire" then ok, msg = actionFireEffect(player, payload.targetName or "", false)
	elseif extraCommandHandlers[action] then ok, msg = extraCommandHandlers[action](player, payload)
	end

	reply(player, msg)
end)

--------------------------------------------------
-- Local Script (StarterPlayerScripts)
--------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local localPlayer = Players.LocalPlayer
local commandEvent = ReplicatedStorage:WaitForChild("AdminCommandEvent")
local ADMIN_USER_IDS = {
	[12345678] = true,
	[87654321] = true,
}
local isAdminLocal = ADMIN_USER_IDS[localPlayer.UserId] == true

pcall(function()
	StarterGui:SetCore("ResetButtonCallback", false)
end)

local gui = Instance.new("ScreenGui")
gui.Name = "AdminMenuGui"
gui.ResetOnSpawn = false
gui.Parent = localPlayer:WaitForChild("PlayerGui")
gui.Enabled = isAdminLocal

local function applyFancyButton(btn, c1, c2)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = btn

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1.2
	stroke.Color = Color3.fromRGB(210, 220, 255)
	stroke.Transparency = 0.45
	stroke.Parent = btn

	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new(c1, c2)
	grad.Rotation = 35
	grad.Parent = btn

	local scale = Instance.new("UIScale")
	scale.Scale = 1
	scale.Parent = btn

	btn.MouseEnter:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.12), { Scale = 1.03 }):Play()
	end)
	btn.MouseLeave:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.12), { Scale = 1 }):Play()
	end)
end

local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, 760, 0, 455)
frame.Position = UDim2.new(0, 24, 0.5, -228)
frame.BackgroundColor3 = Color3.fromRGB(18, 20, 28)
frame.BorderSizePixel = 0
frame.Visible = false
frame.Parent = gui

local frameCorner = Instance.new("UICorner")
frameCorner.CornerRadius = UDim.new(0, 14)
frameCorner.Parent = frame

local frameStroke = Instance.new("UIStroke")
frameStroke.Thickness = 2
frameStroke.Color = Color3.fromRGB(255, 0, 120)
frameStroke.Parent = frame

local frameGrad = Instance.new("UIGradient")
frameGrad.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 0, 140)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(0, 190, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(120, 255, 0)),
})
frameGrad.Parent = frameStroke

local titleBar = Instance.new("Frame")
titleBar.Size = UDim2.new(1, 0, 0, 58)
titleBar.BackgroundColor3 = Color3.fromRGB(24, 28, 40)
titleBar.BorderSizePixel = 0
titleBar.Parent = frame
local titleCorner = Instance.new("UICorner")
titleCorner.CornerRadius = UDim.new(0, 14)
titleCorner.Parent = titleBar

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -20, 0, 34)
title.Position = UDim2.new(0, 10, 0, 6)
title.BackgroundTransparency = 1
title.Text = "⚡ Ultimate Admin Menu V2"
title.TextColor3 = Color3.fromRGB(245, 245, 255)
title.Font = Enum.Font.GothamBlack
title.TextSize = 23
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = titleBar

local subtitle = Instance.new("TextLabel")
subtitle.Size = UDim2.new(1, -20, 0, 18)
subtitle.Position = UDim2.new(0, 10, 0, 35)
subtitle.BackgroundTransparency = 1
subtitle.Text = "F2 — تصميم أوضح + سحب النافذة + أوامر إضافية"
subtitle.TextColor3 = Color3.fromRGB(170, 185, 220)
subtitle.Font = Enum.Font.Gotham
subtitle.TextSize = 12
subtitle.TextXAlignment = Enum.TextXAlignment.Left
subtitle.Parent = titleBar

local topBanner = Instance.new("TextLabel")
topBanner.Size = UDim2.new(0.56, 0, 0, 36)
topBanner.Position = UDim2.new(0.22, 0, 0, 10)
topBanner.BackgroundColor3 = Color3.fromRGB(30, 35, 48)
topBanner.BackgroundTransparency = 0.15
topBanner.TextColor3 = Color3.fromRGB(255, 255, 255)
topBanner.Font = Enum.Font.GothamBold
topBanner.TextSize = 14
topBanner.Visible = false
topBanner.ZIndex = 20
topBanner.Parent = gui
local topCorner = Instance.new("UICorner")
topCorner.CornerRadius = UDim.new(0, 9)
topCorner.Parent = topBanner

local function makeBox(placeholder, y)
	local box = Instance.new("TextBox")
	box.Size = UDim2.new(1, -300, 0, 34)
	box.Position = UDim2.new(0, 10, 0, y)
	box.PlaceholderText = placeholder
	box.Text = ""
	box.ClearTextOnFocus = false
	box.TextColor3 = Color3.fromRGB(245, 245, 255)
	box.BackgroundColor3 = Color3.fromRGB(32, 36, 49)
	box.Font = Enum.Font.Gotham
	box.TextSize = 14
	box.Parent = frame
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 8)
	c.Parent = box
	return box
end

local targetBox = makeBox("اسم اللاعب", 70)
local valueBox = makeBox("السبب/الرسالة/السرعة/UserId/Gravity/Time", 108)

local selectedLabel = Instance.new("TextLabel")
selectedLabel.Size = UDim2.new(1, -300, 0, 22)
selectedLabel.Position = UDim2.new(0, 10, 0, 145)
selectedLabel.BackgroundTransparency = 1
selectedLabel.Text = "اللاعب المختار: لا يوجد"
selectedLabel.TextColor3 = Color3.fromRGB(140, 220, 255)
selectedLabel.Font = Enum.Font.GothamMedium
selectedLabel.TextSize = 13
selectedLabel.TextXAlignment = Enum.TextXAlignment.Left
selectedLabel.Parent = frame

local playersPanel = Instance.new("Frame")
playersPanel.Size = UDim2.new(0, 250, 0, 320)
playersPanel.Position = UDim2.new(1, -280, 0, 70)
playersPanel.BackgroundColor3 = Color3.fromRGB(24, 29, 42)
playersPanel.BorderSizePixel = 0
playersPanel.Parent = frame
local ppCorner = Instance.new("UICorner")
ppCorner.CornerRadius = UDim.new(0, 10)
ppCorner.Parent = playersPanel

local playersTitle = Instance.new("TextLabel")
playersTitle.Size = UDim2.new(1, -12, 0, 28)
playersTitle.Position = UDim2.new(0, 6, 0, 6)
playersTitle.BackgroundTransparency = 1
playersTitle.Text = "اللاعبين في الماب"
playersTitle.TextColor3 = Color3.fromRGB(230, 235, 255)
playersTitle.Font = Enum.Font.GothamBold
playersTitle.TextSize = 14
playersTitle.TextXAlignment = Enum.TextXAlignment.Left
playersTitle.Parent = playersPanel

local playersScroll = Instance.new("ScrollingFrame")
playersScroll.Size = UDim2.new(1, -12, 1, -44)
playersScroll.Position = UDim2.new(0, 6, 0, 34)
playersScroll.BackgroundColor3 = Color3.fromRGB(20, 24, 34)
playersScroll.BorderSizePixel = 0
playersScroll.ScrollBarThickness = 5
playersScroll.CanvasSize = UDim2.new(0,0,0,0)
playersScroll.Parent = playersPanel
local psCorner = Instance.new("UICorner")
psCorner.CornerRadius = UDim.new(0, 8)
psCorner.Parent = playersScroll
local playersLayout = Instance.new("UIListLayout")
playersLayout.Padding = UDim.new(0, 6)
playersLayout.Parent = playersScroll

local buttonContainer = Instance.new("ScrollingFrame")
buttonContainer.Size = UDim2.new(1, -280, 0, 250)
buttonContainer.Position = UDim2.new(0, 10, 0, 175)
buttonContainer.BackgroundColor3 = Color3.fromRGB(20, 24, 34)
buttonContainer.BackgroundTransparency = 0.2
buttonContainer.BorderSizePixel = 0
buttonContainer.ScrollBarThickness = 6
buttonContainer.CanvasSize = UDim2.new(0, 0, 0, 0)
buttonContainer.Parent = frame
local bcCorner = Instance.new("UICorner")
bcCorner.CornerRadius = UDim.new(0, 10)
bcCorner.Parent = buttonContainer
local grid = Instance.new("UIGridLayout")
grid.CellSize = UDim2.new(0.25, -8, 0, 38)
grid.CellPadding = UDim2.new(0, 8, 0, 8)
grid.FillDirectionMaxCells = 4
grid.Parent = buttonContainer

grid:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
	buttonContainer.CanvasSize = UDim2.new(0, 0, 0, grid.AbsoluteContentSize.Y + 8)
end)

local function makeButton(text, c1, c2)
	local btn = Instance.new("TextButton")
	btn.Text = text
	btn.TextColor3 = Color3.new(1,1,1)
	btn.BackgroundColor3 = Color3.fromRGB(50,80,200)
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 12
	btn.Parent = buttonContainer
	applyFancyButton(btn, c1 or Color3.fromRGB(92, 134, 255), c2 or Color3.fromRGB(66, 91, 221))
	return btn
end

local buttons = {
	Kick = makeButton("Kick", Color3.fromRGB(220,90,90), Color3.fromRGB(180,45,45)),
	Ban = makeButton("Ban", Color3.fromRGB(210,75,75), Color3.fromRGB(160,35,35)),
	Unban = makeButton("Unban", Color3.fromRGB(50,180,95), Color3.fromRGB(30,140,70)),
	ShowBanned = makeButton("عرض المتبندين", Color3.fromRGB(150,90,220), Color3.fromRGB(100,60,170)),
	WarnPlayer = makeButton("WarnPlayer", Color3.fromRGB(230,160,40), Color3.fromRGB(180,120,30)),
	WarnServer = makeButton("WarnServer", Color3.fromRGB(255,140,70), Color3.fromRGB(210,95,40)),
	TopMessage = makeButton("TopMessage", Color3.fromRGB(90,160,255), Color3.fromRGB(50,120,220)),
	TeleportTo = makeButton("TeleportTo"),
	BringAll = makeButton("BringAll"),
	Heal = makeButton("Heal", Color3.fromRGB(70,200,140), Color3.fromRGB(40,155,100)),
	God = makeButton("God", Color3.fromRGB(240,200,70), Color3.fromRGB(190,145,20)),
	Ungod = makeButton("Ungod", Color3.fromRGB(120,120,120), Color3.fromRGB(90,90,90)),
	Jail = makeButton("Jail", Color3.fromRGB(180,90,90), Color3.fromRGB(140,60,60)),
	Unjail = makeButton("Unjail", Color3.fromRGB(70,170,100), Color3.fromRGB(40,130,70)),
	Freeze = makeButton("Freeze"),
	Unfreeze = makeButton("Unfreeze"),
	FreezeAll = makeButton("FreezeAll"),
	UnfreezeAll = makeButton("UnfreezeAll"),
	Kill = makeButton("Kill"),
	Pull = makeButton("Pull"),
	SetSpeed = makeButton("SetSpeed"),
	Broadcast = makeButton("Broadcast", Color3.fromRGB(90,140,245), Color3.fromRGB(60,90,210)),
	SetJump = makeButton("SetJumpPower", Color3.fromRGB(65,150,245), Color3.fromRGB(35,110,210)),
	Invis = makeButton("Invis", Color3.fromRGB(120,95,210), Color3.fromRGB(80,65,170)),
	Reveal = makeButton("Reveal", Color3.fromRGB(65,180,225), Color3.fromRGB(40,130,180)),
	Sparkles = makeButton("Sparkles", Color3.fromRGB(255,185,80), Color3.fromRGB(220,130,50)),
	Unsparkles = makeButton("Unsparkles", Color3.fromRGB(140,140,160), Color3.fromRGB(95,95,115)),
	Spectate = makeButton("Spectate", Color3.fromRGB(150,115,255), Color3.fromRGB(105,70,210)),
	Unspectate = makeButton("Unspectate", Color3.fromRGB(100,170,255), Color3.fromRGB(60,120,205)),
	Respawn = makeButton("Respawn", Color3.fromRGB(70,190,150), Color3.fromRGB(45,145,110)),
	ForceField = makeButton("ForceField", Color3.fromRGB(140,210,255), Color3.fromRGB(80,160,220)),
	UnforceField = makeButton("UnforceField", Color3.fromRGB(120,140,165), Color3.fromRGB(80,95,120)),
	SetGravity = makeButton("SetGravity", Color3.fromRGB(255,160,90), Color3.fromRGB(220,115,50)),
	SetTime = makeButton("SetTime", Color3.fromRGB(120,130,255), Color3.fromRGB(75,90,215)),
	Explode = makeButton("Explode", Color3.fromRGB(255,95,70), Color3.fromRGB(210,55,40)),
	Fire = makeButton("Fire", Color3.fromRGB(255,165,70), Color3.fromRGB(225,110,40)),
	Unfire = makeButton("Unfire", Color3.fromRGB(130,145,160), Color3.fromRGB(90,100,120)),
}

local extraActionButtons = {
	{key="X_SetHealth", action="SetHealth", label="SetHP", kind="valueTarget"},
	{key="X_SetMaxHealth", action="SetMaxHealth", label="SetMaxHP", kind="valueTarget"},
	{key="X_Damage", action="Damage", label="Damage", kind="target"},
	{key="X_DamageAll", action="DamageAll", label="DamageAll", kind="none"},
	{key="X_HealAll", action="HealAll", label="HealAll", kind="none"},
	{key="X_Slow", action="Slow", label="Slow", kind="target"},
	{key="X_Fast", action="Fast", label="Fast", kind="target"},
	{key="X_ResetSpeed", action="ResetSpeed", label="ResetSpd", kind="target"},
	{key="X_JumpBoost", action="JumpBoost", label="Jump+", kind="target"},
	{key="X_ResetJump", action="ResetJump", label="ResetJump", kind="target"},
	{key="X_Sit", action="Sit", label="Sit", kind="target"},
	{key="X_Unsit", action="Unsit", label="Unsit", kind="target"},
	{key="X_Tiny", action="Tiny", label="Tiny", kind="target"},
	{key="X_Big", action="Big", label="Big", kind="target"},
	{key="X_NormalSize", action="NormalSize", label="NormalSize", kind="target"},
	{key="X_Noclip", action="Noclip", label="Noclip", kind="target"},
	{key="X_Clip", action="Clip", label="Clip", kind="target"},
	{key="X_Spin", action="Spin", label="Spin", kind="target"},
	{key="X_Unspin", action="Unspin", label="Unspin", kind="target"},
	{key="X_Fling", action="Fling", label="Fling", kind="target"},
	{key="X_Trip", action="Trip", label="Trip", kind="target"},
	{key="X_Stun", action="Stun", label="Stun", kind="target"},
	{key="X_Unstun", action="Unstun", label="Unstun", kind="target"},
	{key="X_Launch", action="Launch", label="Launch", kind="target"},
	{key="X_Shockwave", action="Shockwave", label="Shockwave", kind="target"},
	{key="X_RespawnAll", action="RespawnAll", label="RespawnAll", kind="none"},
	{key="X_KickAll", action="KickAll", label="KickAll", kind="none"},
	{key="X_GodAll", action="GodAll", label="GodAll", kind="none"},
	{key="X_UngodAll", action="UngodAll", label="UngodAll", kind="none"},
	{key="X_SparklesAll", action="SparklesAll", label="SparklesAll", kind="none"},
	{key="X_UnsparklesAll", action="UnsparklesAll", label="UnsparklesAll", kind="none"},
	{key="X_FireAll", action="FireAll", label="FireAll", kind="none"},
	{key="X_UnfireAll", action="UnfireAll", label="UnfireAll", kind="none"},
	{key="X_InvisAll", action="InvisAll", label="InvisAll", kind="none"},
	{key="X_RevealAll", action="RevealAll", label="RevealAll", kind="none"},
	{key="X_GravityLow", action="GravityLow", label="GravityLow", kind="none"},
	{key="X_GravityNormal", action="GravityNormal", label="GravityNorm", kind="none"},
	{key="X_GravityHigh", action="GravityHigh", label="GravityHigh", kind="none"},
	{key="X_TimeDay", action="TimeDay", label="TimeDay", kind="none"},
	{key="X_TimeNight", action="TimeNight", label="TimeNight", kind="none"},
	{key="X_TimeNoon", action="TimeNoon", label="TimeNoon", kind="none"},
	{key="X_TimeMidnight", action="TimeMidnight", label="Midnight", kind="none"},
	{key="X_FogOn", action="FogOn", label="FogOn", kind="none"},
	{key="X_FogOff", action="FogOff", label="FogOff", kind="none"},
	{key="X_BrightLow", action="BrightLow", label="BrightLow", kind="none"},
	{key="X_BrightNormal", action="BrightNormal", label="BrightNorm", kind="none"},
		{key="X_BrightHigh", action="BrightHigh", label="BrightHigh", kind="none"},
		{key="X_LockMap", action="LockMap", label="LockMap", kind="none"},
		{key="X_UnlockMap", action="UnlockMap", label="UnlockMap", kind="none"},
		{key="X_KillAll", action="KillAll", label="KillAll", kind="none"},
		{key="X2_HP25", action="HP25", label="HP25", kind="target"},
		{key="X2_HP50", action="HP50", label="HP50", kind="target"},
		{key="X2_HP75", action="HP75", label="HP75", kind="target"},
		{key="X2_HP100", action="HP100", label="HP100", kind="target"},
		{key="X2_HP200", action="HP200", label="HP200", kind="target"},
		{key="X2_Damage5", action="Damage5", label="Dmg5", kind="target"},
		{key="X2_Damage15", action="Damage15", label="Dmg15", kind="target"},
		{key="X2_Damage30", action="Damage30", label="Dmg30", kind="target"},
		{key="X2_Damage60", action="Damage60", label="Dmg60", kind="target"},
		{key="X2_Damage95", action="Damage95", label="Dmg95", kind="target"},
		{key="X2_Speed12", action="Speed12", label="Speed12", kind="target"},
		{key="X2_Speed24", action="Speed24", label="Speed24", kind="target"},
		{key="X2_Speed48", action="Speed48", label="Speed48", kind="target"},
		{key="X2_Speed64", action="Speed64", label="Speed64", kind="target"},
		{key="X2_Speed96", action="Speed96", label="Speed96", kind="target"},
		{key="X2_Jump30", action="Jump30", label="Jump30", kind="target"},
		{key="X2_Jump60", action="Jump60", label="Jump60", kind="target"},
		{key="X2_Jump100", action="Jump100", label="Jump100", kind="target"},
		{key="X2_Jump140", action="Jump140", label="Jump140", kind="target"},
		{key="X2_Jump200", action="Jump200", label="Jump200", kind="target"},
		{key="X2_Gravity40", action="Gravity40", label="Grav40", kind="none"},
		{key="X2_Gravity70", action="Gravity70", label="Grav70", kind="none"},
		{key="X2_Gravity110", action="Gravity110", label="Grav110", kind="none"},
		{key="X2_Gravity150", action="Gravity150", label="Grav150", kind="none"},
		{key="X2_Gravity210", action="Gravity210", label="Grav210", kind="none"},
		{key="X2_TimeSunrise", action="TimeSunrise", label="Sunrise", kind="none"},
		{key="X2_TimeMorning", action="TimeMorning", label="Morning", kind="none"},
		{key="X2_TimeEvening", action="TimeEvening", label="Evening", kind="none"},
		{key="X2_TimeLateNight", action="TimeLateNight", label="LateNight", kind="none"},
		{key="X2_TimeDawn", action="TimeDawn", label="Dawn", kind="none"},
		{key="X2_FreezeEveryone", action="FreezeEveryone", label="FreezeAll2", kind="none"},
		{key="X2_UnfreezeEveryone", action="UnfreezeEveryone", label="Unfreeze2", kind="none"},
		{key="X2_PullEveryone", action="PullEveryone", label="PullAll2", kind="none"},
		{key="X2_BringRandom", action="BringRandom", label="BringRnd", kind="none"},
		{key="X2_ScatterAll", action="ScatterAll", label="ScatterAll", kind="none"},
		{key="X2_SparklesRainbow", action="SparklesRainbow", label="SparkleRB", kind="none"},
		{key="X2_FireGreen", action="FireGreen", label="FireGreen", kind="none"},
		{key="X2_Confetti", action="Confetti", label="Confetti", kind="none"},
		{key="X2_SmokeOn", action="SmokeOn", label="SmokeOn", kind="none"},
		{key="X2_SmokeOff", action="SmokeOff", label="SmokeOff", kind="none"},
		{key="X2_BlindAll", action="BlindAll", label="BlindAll", kind="none"},
		{key="X2_UnblindAll", action="UnblindAll", label="Unblind", kind="none"},
		{key="X2_LowHealthAll", action="LowHealthAll", label="LowHPAll", kind="none"},
		{key="X2_MaxHealthAll", action="MaxHealthAll", label="MaxHPAll", kind="none"},
		{key="X2_ResetAllStats", action="ResetAllStats", label="ResetStats", kind="none"},
		{key="X2_BounceAll", action="BounceAll", label="BounceAll", kind="none"},
		{key="X2_StopAllVelocity", action="StopAllVelocity", label="StopVel", kind="none"},
		{key="X2_AnchorAll", action="AnchorAll", label="AnchorAll", kind="none"},
		{key="X2_UnanchorAll", action="UnanchorAll", label="Unanchor", kind="none"},
		{key="X2_CleanMapEffects", action="CleanMapEffects", label="CleanFX", kind="none"},
	}

for _, def in ipairs(extraActionButtons) do
	buttons[def.key] = makeButton(def.label, Color3.fromRGB(118, 145, 255), Color3.fromRGB(70, 94, 200))
end

local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, -20, 0, 22)
status.Position = UDim2.new(0, 10, 1, -28)
status.BackgroundTransparency = 1
status.TextColor3 = Color3.fromRGB(255, 230, 120)
status.Font = Enum.Font.GothamMedium
status.TextSize = 13
status.TextXAlignment = Enum.TextXAlignment.Left
status.Text = "جاهز"
status.Parent = frame

local bannedFrame = Instance.new("Frame")
bannedFrame.Size = UDim2.new(0, 520, 0, 320)
bannedFrame.Position = UDim2.new(0.5, -260, 0.5, -160)
bannedFrame.BackgroundColor3 = Color3.fromRGB(22, 26, 38)
bannedFrame.BorderSizePixel = 0
bannedFrame.Visible = false
bannedFrame.Parent = gui
local bfCorner = Instance.new("UICorner")
bfCorner.CornerRadius = UDim.new(0, 12)
bfCorner.Parent = bannedFrame

local bannedTitleBar = Instance.new("Frame")
bannedTitleBar.Size = UDim2.new(1,0,0,38)
bannedTitleBar.BackgroundColor3 = Color3.fromRGB(35,40,58)
bannedTitleBar.Parent = bannedFrame
local btbCorner = Instance.new("UICorner")
btbCorner.CornerRadius = UDim.new(0, 12)
btbCorner.Parent = bannedTitleBar

local bannedTitle = Instance.new("TextLabel")
bannedTitle.Size = UDim2.new(1, -90, 1, 0)
bannedTitle.Position = UDim2.new(0, 10, 0, 0)
bannedTitle.BackgroundTransparency = 1
bannedTitle.Text = "📋 قائمة المتبندين"
bannedTitle.TextColor3 = Color3.fromRGB(240,240,255)
bannedTitle.Font = Enum.Font.GothamBold
bannedTitle.TextSize = 18
bannedTitle.TextXAlignment = Enum.TextXAlignment.Left
bannedTitle.Parent = bannedTitleBar

local closeBannedBtn = Instance.new("TextButton")
closeBannedBtn.Size = UDim2.new(0, 70, 0, 26)
closeBannedBtn.Position = UDim2.new(1, -78, 0, 6)
closeBannedBtn.Text = "إغلاق"
closeBannedBtn.Font = Enum.Font.GothamBold
closeBannedBtn.TextSize = 12
closeBannedBtn.Parent = bannedTitleBar
applyFancyButton(closeBannedBtn, Color3.fromRGB(220,95,95), Color3.fromRGB(170,60,60))

local bannedScroll = Instance.new("ScrollingFrame")
bannedScroll.Size = UDim2.new(1, -20, 1, -50)
bannedScroll.Position = UDim2.new(0, 10, 0, 42)
bannedScroll.BackgroundColor3 = Color3.fromRGB(18, 22, 32)
bannedScroll.BorderSizePixel = 0
bannedScroll.ScrollBarThickness = 6
bannedScroll.CanvasSize = UDim2.new(0,0,0,0)
bannedScroll.Parent = bannedFrame
local bscCorner = Instance.new("UICorner")
bscCorner.CornerRadius = UDim.new(0, 8)
bscCorner.Parent = bannedScroll
local bannedLayout = Instance.new("UIListLayout")
bannedLayout.Padding = UDim.new(0,6)
bannedLayout.Parent = bannedScroll

local selectedPlayerName = nil

local function setSelectedPlayer(name)
	selectedPlayerName = name
	targetBox.Text = name or ""
	selectedLabel.Text = "اللاعب المختار: " .. (name or "لا يوجد")
end

local function createPlayerButton(player)
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(1,-8,0,30)
	btn.Text = "  " .. player.Name
	btn.TextXAlignment = Enum.TextXAlignment.Left
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 13
	btn.TextColor3 = Color3.new(1,1,1)
	btn.Parent = playersScroll
	applyFancyButton(btn, Color3.fromRGB(85,130,255), Color3.fromRGB(58,95,210))
	btn.MouseButton1Click:Connect(function()
		setSelectedPlayer(player.Name)
	end)
end

local function refreshPlayersList()
	for _, c in ipairs(playersScroll:GetChildren()) do
		if c:IsA("TextButton") then c:Destroy() end
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= localPlayer then createPlayerButton(p) end
	end
	task.wait()
	playersScroll.CanvasSize = UDim2.new(0,0,0,playersLayout.AbsoluteContentSize.Y + 8)
	if selectedPlayerName and not Players:FindFirstChild(selectedPlayerName) then
		setSelectedPlayer(nil)
	end
end

local function clearBannedRows()
	for _, c in ipairs(bannedScroll:GetChildren()) do
		if c:IsA("Frame") then c:Destroy() end
	end
end

local function createBannedRow(item)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1,-8,0,72)
	row.BackgroundColor3 = Color3.fromRGB(30,36,50)
	row.BorderSizePixel = 0
	row.Parent = bannedScroll
	local rcorner = Instance.new("UICorner")
	rcorner.CornerRadius = UDim.new(0,8)
	rcorner.Parent = row

	local info = Instance.new("TextLabel")
	info.Size = UDim2.new(1,-86,1,-8)
	info.Position = UDim2.new(0,8,0,4)
	info.BackgroundTransparency = 1
	info.TextWrapped = true
	info.TextXAlignment = Enum.TextXAlignment.Left
	info.TextYAlignment = Enum.TextYAlignment.Top
	info.Font = Enum.Font.Gotham
	info.TextSize = 12
	info.TextColor3 = Color3.fromRGB(230,235,250)
	info.Text = string.format("الاسم: %s | UserId: %s\nالسبب: %s\nبواسطة: %s (%s)", tostring(item.playerName), tostring(item.userId), tostring(item.reason), tostring(item.adminName), tostring(item.adminUserId))
	info.Parent = row

	local unbanBtn = Instance.new("TextButton")
	unbanBtn.Size = UDim2.new(0,70,0,28)
	unbanBtn.Position = UDim2.new(1,-78,0.5,-14)
	unbanBtn.Text = "فك باند"
	unbanBtn.Font = Enum.Font.GothamBold
	unbanBtn.TextSize = 12
	unbanBtn.TextColor3 = Color3.new(1,1,1)
	unbanBtn.Parent = row
	applyFancyButton(unbanBtn, Color3.fromRGB(60,175,100), Color3.fromRGB(40,140,75))
	unbanBtn.MouseButton1Click:Connect(function()
		commandEvent:FireServer("Unban", { userId = tostring(item.userId) })
		commandEvent:FireServer("ShowBanned", {})
	end)
end

local function getTargetName()
	if targetBox.Text ~= "" then return targetBox.Text end
	return selectedPlayerName or ""
end

buttons.Kick.MouseButton1Click:Connect(function() commandEvent:FireServer("Kick", { targetName = getTargetName(), reason = valueBox.Text }) end)
buttons.Ban.MouseButton1Click:Connect(function() commandEvent:FireServer("Ban", { targetName = getTargetName(), reason = valueBox.Text }); commandEvent:FireServer("ShowBanned", {}) end)
buttons.Unban.MouseButton1Click:Connect(function() commandEvent:FireServer("Unban", { userId = valueBox.Text }); commandEvent:FireServer("ShowBanned", {}) end)
buttons.ShowBanned.MouseButton1Click:Connect(function() bannedFrame.Visible = true; commandEvent:FireServer("ShowBanned", {}) end)
buttons.WarnPlayer.MouseButton1Click:Connect(function() commandEvent:FireServer("WarnPlayer", { targetName = getTargetName(), message = valueBox.Text }) end)
buttons.WarnServer.MouseButton1Click:Connect(function() commandEvent:FireServer("WarnServer", { message = valueBox.Text }) end)
buttons.TopMessage.MouseButton1Click:Connect(function() commandEvent:FireServer("TopMessage", { message = valueBox.Text }) end)
buttons.TeleportTo.MouseButton1Click:Connect(function() commandEvent:FireServer("TeleportTo", { targetName = getTargetName() }) end)
buttons.BringAll.MouseButton1Click:Connect(function() commandEvent:FireServer("BringAll", {}) end)
buttons.Heal.MouseButton1Click:Connect(function() commandEvent:FireServer("Heal", { targetName = getTargetName() }) end)
buttons.God.MouseButton1Click:Connect(function() commandEvent:FireServer("God", { targetName = getTargetName() }) end)
buttons.Ungod.MouseButton1Click:Connect(function() commandEvent:FireServer("Ungod", { targetName = getTargetName() }) end)
buttons.Jail.MouseButton1Click:Connect(function() commandEvent:FireServer("Jail", { targetName = getTargetName() }) end)
buttons.Unjail.MouseButton1Click:Connect(function() commandEvent:FireServer("Unjail", { targetName = getTargetName() }) end)
buttons.Freeze.MouseButton1Click:Connect(function() commandEvent:FireServer("Freeze", { targetName = getTargetName() }) end)
buttons.Unfreeze.MouseButton1Click:Connect(function() commandEvent:FireServer("Unfreeze", { targetName = getTargetName() }) end)
buttons.FreezeAll.MouseButton1Click:Connect(function() commandEvent:FireServer("FreezeAll", {}) end)
buttons.UnfreezeAll.MouseButton1Click:Connect(function() commandEvent:FireServer("UnfreezeAll", {}) end)
buttons.Kill.MouseButton1Click:Connect(function() commandEvent:FireServer("Kill", { targetName = getTargetName() }) end)
buttons.Pull.MouseButton1Click:Connect(function() commandEvent:FireServer("Pull", { targetName = getTargetName() }) end)
buttons.SetSpeed.MouseButton1Click:Connect(function() commandEvent:FireServer("SetWalkSpeed", { targetName = getTargetName(), speed = valueBox.Text }) end)
buttons.Broadcast.MouseButton1Click:Connect(function() commandEvent:FireServer("Broadcast", { message = valueBox.Text }) end)
buttons.SetJump.MouseButton1Click:Connect(function() commandEvent:FireServer("SetJumpPower", { targetName = getTargetName(), jumpPower = valueBox.Text }) end)
buttons.Invis.MouseButton1Click:Connect(function() commandEvent:FireServer("Invis", { targetName = getTargetName() }) end)
buttons.Reveal.MouseButton1Click:Connect(function() commandEvent:FireServer("Reveal", { targetName = getTargetName() }) end)
buttons.Sparkles.MouseButton1Click:Connect(function() commandEvent:FireServer("Sparkles", { targetName = getTargetName() }) end)
buttons.Unsparkles.MouseButton1Click:Connect(function() commandEvent:FireServer("Unsparkles", { targetName = getTargetName() }) end)
buttons.Spectate.MouseButton1Click:Connect(function() commandEvent:FireServer("Spectate", { targetName = getTargetName() }) end)
buttons.Unspectate.MouseButton1Click:Connect(function() commandEvent:FireServer("Unspectate", {}) end)
buttons.Respawn.MouseButton1Click:Connect(function() commandEvent:FireServer("Respawn", { targetName = getTargetName() }) end)
buttons.ForceField.MouseButton1Click:Connect(function() commandEvent:FireServer("ForceField", { targetName = getTargetName() }) end)
buttons.UnforceField.MouseButton1Click:Connect(function() commandEvent:FireServer("UnforceField", { targetName = getTargetName() }) end)
buttons.SetGravity.MouseButton1Click:Connect(function() commandEvent:FireServer("SetGravity", { value = valueBox.Text }) end)
buttons.SetTime.MouseButton1Click:Connect(function() commandEvent:FireServer("SetTime", { value = valueBox.Text }) end)
buttons.Explode.MouseButton1Click:Connect(function() commandEvent:FireServer("Explode", { targetName = getTargetName() }) end)
buttons.Fire.MouseButton1Click:Connect(function() commandEvent:FireServer("Fire", { targetName = getTargetName() }) end)
buttons.Unfire.MouseButton1Click:Connect(function() commandEvent:FireServer("Unfire", { targetName = getTargetName() }) end)

local function buildPayload(kind)
	if kind == "target" then
		return { targetName = getTargetName() }
	elseif kind == "valueTarget" then
		return { targetName = getTargetName(), value = valueBox.Text }
	end
	return {}
end

for _, def in ipairs(extraActionButtons) do
	buttons[def.key].MouseButton1Click:Connect(function()
		commandEvent:FireServer(def.action, buildPayload(def.kind))
	end)
end

if isAdminLocal and UserInputService.TouchEnabled then
	local mobileBtn = Instance.new("TextButton")
	mobileBtn.Name = "AdminOpenMobile"
	mobileBtn.Size = UDim2.new(0, 56, 0, 56)
	mobileBtn.Position = UDim2.new(1, -70, 1, -72)
	mobileBtn.Text = "ADM"
	mobileBtn.Font = Enum.Font.GothamBlack
	mobileBtn.TextSize = 14
	mobileBtn.TextColor3 = Color3.new(1, 1, 1)
	mobileBtn.BackgroundColor3 = Color3.fromRGB(85, 125, 255)
	mobileBtn.ZIndex = 30
	mobileBtn.Parent = gui
	applyFancyButton(mobileBtn, Color3.fromRGB(90, 140, 255), Color3.fromRGB(60, 95, 220))
	mobileBtn.MouseButton1Click:Connect(function()
		frame.Visible = not frame.Visible
	end)
end

closeBannedBtn.MouseButton1Click:Connect(function() bannedFrame.Visible = false end)

local activeBannerTween = nil
local spectateConn = nil

local function showTopBanner(prefix, message, holdTime)
	topBanner.Text = prefix .. tostring(message)
	topBanner.TextTransparency = 1
	topBanner.BackgroundTransparency = 1
	topBanner.Visible = true
	if activeBannerTween then activeBannerTween:Cancel() end
	local fadeIn = TweenService:Create(topBanner, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {TextTransparency = 0, BackgroundTransparency = 0.15})
	fadeIn:Play()
	task.delay(holdTime or 3.8, function()
		local fadeOut = TweenService:Create(topBanner, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {TextTransparency = 1, BackgroundTransparency = 1})
		activeBannerTween = fadeOut
		fadeOut:Play()
		fadeOut.Completed:Wait()
		topBanner.Visible = false
	end)
end

local function stopSpectate()
	if spectateConn then spectateConn:Disconnect() spectateConn = nil end
	workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
	workspace.CurrentCamera.CameraSubject = localPlayer.Character and localPlayer.Character:FindFirstChildOfClass("Humanoid")
end

commandEvent.OnClientEvent:Connect(function(eventType, message)
	if eventType == "SystemMessage" then
		status.Text = tostring(message)
	elseif eventType == "BroadcastMessage" then
		status.Text = "📢 " .. tostring(message)
	elseif eventType == "WarningMessage" then
		status.Text = "⚠️ " .. tostring(message)
		showTopBanner("⚠️ ", message, 4)
	elseif eventType == "TopMessage" then
		showTopBanner("📣 ", message, 4.8)
	elseif eventType == "SpectateStart" then
		local target = Players:FindFirstChild(tostring(message))
		if not target or not target.Character then
			status.Text = "لا يمكن بدء المشاهدة"
			return
		end
		if spectateConn then spectateConn:Disconnect() end
		workspace.CurrentCamera.CameraType = Enum.CameraType.Scriptable
		spectateConn = RunService.RenderStepped:Connect(function()
			local root = target.Character and target.Character:FindFirstChild("HumanoidRootPart")
			if root then
				workspace.CurrentCamera.CFrame = root.CFrame * CFrame.new(0, 5, 12)
			end
		end)
		status.Text = "🎥 تتم مشاهدة " .. tostring(message)
	elseif eventType == "SpectateStop" then
		stopSpectate()
		status.Text = "تم إيقاف المشاهدة"
	elseif eventType == "BannedList" then
		clearBannedRows()
		for _, item in ipairs(message) do createBannedRow(item) end
		task.wait()
		bannedScroll.CanvasSize = UDim2.new(0, 0, 0, bannedLayout.AbsoluteContentSize.Y + 8)
	end
end)

UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.KeyCode == Enum.KeyCode.F2 then
		frame.Visible = not frame.Visible
	end
end)

local function enableDrag(dragHandle, dragTarget)
	local dragging = false
	local dragStart, startPos
	local function update(input)
		local delta = input.Position - dragStart
		dragTarget.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
	end
	dragHandle.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = true
			dragStart = input.Position
			startPos = dragTarget.Position
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then dragging = false end
			end)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
			update(input)
		end
	end)
end

enableDrag(titleBar, frame)
enableDrag(bannedTitleBar, bannedFrame)

RunService.RenderStepped:Connect(function(dt)
	frameGrad.Rotation = (frameGrad.Rotation + dt * 80) % 360
	frameStroke.Color = Color3.fromHSV((tick() * 0.2) % 1, 1, 1)
end)

Players.PlayerAdded:Connect(refreshPlayersList)
Players.PlayerRemoving:Connect(refreshPlayersList)
refreshPlayersList()

localPlayer.CharacterAdded:Connect(function()
	stopSpectate()
end)
