--!strict
-- Roblox Police Report System (Client)
-- Place in StarterPlayer > StarterPlayerScripts

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local POLICE_TEAM_NAME = "Police"
local ARRIVAL_DISTANCE = 10

local player = Players.LocalPlayer
local remotesFolder = ReplicatedStorage:WaitForChild("ReportRemotes")

local submitReport = remotesFolder:WaitForChild("SubmitReport") :: RemoteEvent
local reviewReport = remotesFolder:WaitForChild("ReviewReport") :: RemoteEvent
local reportApprovedNotify = remotesFolder:WaitForChild("ReportApprovedNotify") :: RemoteEvent
local reportStatusUpdate = remotesFolder:WaitForChild("ReportStatusUpdate") :: RemoteEvent
local policeInboxUpdate = remotesFolder:WaitForChild("PoliceInboxUpdate") :: RemoteEvent
local getPendingReports = remotesFolder:WaitForChild("GetPendingReports") :: RemoteFunction

type PendingReport = {
    reportId: string,
    reporterName: string,
    suspectName: string,
    reason: string,
    createdAt: number,
}

local pendingReports: {[string]: PendingReport} = {}

local targetPart: Part? = nil
local arrowBillboard: BillboardGui? = nil
local beamPart: Part? = nil
local heartbeatConnection: RBXScriptConnection? = nil

local openedModal: Frame? = nil
local viewportConnection: RBXScriptConnection? = nil

local function isPoliceLocal(): boolean
    return player.Team ~= nil and player.Team.Name == POLICE_TEAM_NAME
end

local function createCorner(parent: Instance, radius: number)
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, radius)
    corner.Parent = parent
end

local function addStroke(parent: Instance, color: Color3, thickness: number, transparency: number?)
    local stroke = Instance.new("UIStroke")
    stroke.Color = color
    stroke.Thickness = thickness
    stroke.Transparency = transparency or 0
    stroke.Parent = parent
end

local function addGradient(parent: Instance, colors: {Color3}, rotation: number)
    local gradient = Instance.new("UIGradient")
    local points: {ColorSequenceKeypoint} = {}
    for i, color in ipairs(colors) do
        local alpha = 0
        if #colors > 1 then
            alpha = (i - 1) / (#colors - 1)
        end
        table.insert(points, ColorSequenceKeypoint.new(alpha, color))
    end
    gradient.Color = ColorSequence.new(points)
    gradient.Rotation = rotation
    gradient.Parent = parent
end

local function animateButton(button: TextButton)
    button.MouseEnter:Connect(function()
        TweenService:Create(button, TweenInfo.new(0.12), {
            BackgroundTransparency = 0.08,
        }):Play()
    end)

    button.MouseLeave:Connect(function()
        TweenService:Create(button, TweenInfo.new(0.12), {
            BackgroundTransparency = 0,
        }):Play()
    end)
end

local function formatTimeAgo(createdAt: number): string
    local diff = math.max(0, os.time() - createdAt)
    if diff < 60 then
        return "الآن"
    elseif diff < 3600 then
        return string.format("منذ %d د", math.floor(diff / 60))
    else
        return string.format("منذ %d س", math.floor(diff / 3600))
    end
end

local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

local mainGui = Instance.new("ScreenGui")
mainGui.Name = "ReportMainGui"
mainGui.ResetOnSpawn = false
mainGui.IgnoreGuiInset = true
mainGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
mainGui.Parent = playerGui

local toastLayer = Instance.new("Frame")
toastLayer.BackgroundTransparency = 1
toastLayer.Size = UDim2.fromScale(1, 1)
toastLayer.Parent = mainGui

local modalBlocker = Instance.new("TextButton")
modalBlocker.Size = UDim2.fromScale(1, 1)
modalBlocker.Text = ""
modalBlocker.AutoButtonColor = false
modalBlocker.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
modalBlocker.BackgroundTransparency = 0.4
modalBlocker.Visible = false
modalBlocker.ZIndex = 29
modalBlocker.Parent = mainGui

local safeArea = Instance.new("Frame")
safeArea.BackgroundTransparency = 1
safeArea.Size = UDim2.fromScale(1, 1)
safeArea.Parent = mainGui

local function showFancyNotification(title: string, message: string)
    local card = Instance.new("Frame")
    card.Size = UDim2.fromOffset(420, 98)
    card.AnchorPoint = Vector2.new(1, 0)
    card.Position = UDim2.new(1, 420, 0, 20)
    card.BackgroundColor3 = Color3.fromRGB(16, 23, 37)
    card.BorderSizePixel = 0
    card.ZIndex = 50
    card.Parent = toastLayer

    createCorner(card, 14)
    addStroke(card, Color3.fromRGB(255, 85, 85), 2)
    addGradient(card, {Color3.fromRGB(19, 27, 45), Color3.fromRGB(14, 20, 33)}, 45)

    local icon = Instance.new("TextLabel")
    icon.BackgroundTransparency = 1
    icon.Size = UDim2.fromOffset(28, 28)
    icon.Position = UDim2.fromOffset(12, 12)
    icon.Text = "🔔"
    icon.TextScaled = true
    icon.ZIndex = 52
    icon.Parent = card

    local titleLabel = Instance.new("TextLabel")
    titleLabel.BackgroundTransparency = 1
    titleLabel.Size = UDim2.new(1, -52, 0, 30)
    titleLabel.Position = UDim2.fromOffset(40, 8)
    titleLabel.TextXAlignment = Enum.TextXAlignment.Right
    titleLabel.Font = Enum.Font.GothamBold
    titleLabel.TextSize = 19
    titleLabel.TextColor3 = Color3.fromRGB(255, 105, 105)
    titleLabel.Text = title
    titleLabel.ZIndex = 52
    titleLabel.Parent = card

    local body = Instance.new("TextLabel")
    body.BackgroundTransparency = 1
    body.Size = UDim2.new(1, -20, 0, 50)
    body.Position = UDim2.fromOffset(10, 40)
    body.TextXAlignment = Enum.TextXAlignment.Right
    body.TextYAlignment = Enum.TextYAlignment.Top
    body.TextWrapped = true
    body.Font = Enum.Font.GothamSemibold
    body.TextSize = 14
    body.TextColor3 = Color3.fromRGB(236, 242, 255)
    body.Text = message
    body.ZIndex = 52
    body.Parent = card

    TweenService:Create(card, TweenInfo.new(0.35, Enum.EasingStyle.Quint), {
        Position = UDim2.new(1, -18, 0, 20),
    }):Play()

    task.delay(4.5, function()
        local tween = TweenService:Create(card, TweenInfo.new(0.3, Enum.EasingStyle.Quint), {
            Position = UDim2.new(1, 440, 0, 20),
        })
        tween:Play()
        tween.Completed:Wait()
        card:Destroy()
    end)
end

local function clearGuidance()
    if heartbeatConnection then
        heartbeatConnection:Disconnect()
        heartbeatConnection = nil
    end

    if arrowBillboard then
        arrowBillboard:Destroy()
        arrowBillboard = nil
    end

    if beamPart then
        beamPart:Destroy()
        beamPart = nil
    end

    if targetPart then
        targetPart:Destroy()
        targetPart = nil
    end
end

local function setupGuidance(targetPosition: Vector3)
    clearGuidance()

    targetPart = Instance.new("Part")
    targetPart.Name = "ApprovedReportTarget"
    targetPart.Anchored = true
    targetPart.CanCollide = false
    targetPart.Transparency = 1
    targetPart.Size = Vector3.new(1, 1, 1)
    targetPart.Position = targetPosition
    targetPart.Parent = workspace

    arrowBillboard = Instance.new("BillboardGui")
    arrowBillboard.Size = UDim2.fromOffset(80, 80)
    arrowBillboard.StudsOffset = Vector3.new(0, 7, 0)
    arrowBillboard.AlwaysOnTop = true
    arrowBillboard.Parent = targetPart

    local arrow = Instance.new("TextLabel")
    arrow.BackgroundTransparency = 1
    arrow.Size = UDim2.fromScale(1, 1)
    arrow.Font = Enum.Font.GothamBlack
    arrow.TextScaled = true
    arrow.Text = "⬇"
    arrow.TextColor3 = Color3.fromRGB(255, 20, 20)
    arrow.Parent = arrowBillboard

    beamPart = Instance.new("Part")
    beamPart.Name = "ReportBeam"
    beamPart.Anchored = true
    beamPart.CanCollide = false
    beamPart.Material = Enum.Material.Neon
    beamPart.Color = Color3.fromRGB(255, 0, 0)
    beamPart.Transparency = 0.25
    beamPart.Parent = workspace

    heartbeatConnection = RunService.Heartbeat:Connect(function()
        local character = player.Character
        local root = character and character:FindFirstChild("HumanoidRootPart")
        if not root or not root:IsA("BasePart") or not targetPart or not beamPart then
            return
        end

        local fromPos = root.Position
        local toPos = targetPart.Position
        local distance = (toPos - fromPos).Magnitude

        if distance <= ARRIVAL_DISTANCE then
            showFancyNotification("لقد وصلت", "تم الوصول لموقع البلاغ.")
            clearGuidance()
            return
        end

        local midpoint = (fromPos + toPos) / 2
        beamPart.Size = Vector3.new(0.4, 0.4, distance)
        beamPart.CFrame = CFrame.lookAt(midpoint, toPos)
    end)
end

local function openModal(modal: Frame)
    if openedModal and openedModal ~= modal then
        openedModal.Visible = false
    end
    openedModal = modal
    modal.Visible = true
    modalBlocker.Visible = true
end

local function closeModal(modal: Frame)
    modal.Visible = false
    if openedModal == modal then
        openedModal = nil
    end
    modalBlocker.Visible = openedModal ~= nil
end

modalBlocker.MouseButton1Click:Connect(function()
    if openedModal then
        openedModal.Visible = false
        openedModal = nil
    end
    modalBlocker.Visible = false
end)

-- Left side control dock (responsive)
local dock = Instance.new("Frame")
dock.AnchorPoint = Vector2.new(0, 0.5)
dock.Position = UDim2.new(0, 14, 0.5, 0)
dock.Size = UDim2.fromOffset(250, 160)
dock.BackgroundColor3 = Color3.fromRGB(16, 21, 34)
dock.BorderSizePixel = 0
dock.ZIndex = 22
dock.Parent = safeArea
createCorner(dock, 16)
addStroke(dock, Color3.fromRGB(72, 92, 138), 1, 0.25)
addGradient(dock, {Color3.fromRGB(18, 26, 42), Color3.fromRGB(14, 19, 32)}, 35)

local dockScale = Instance.new("UIScale")
dockScale.Scale = 1
dockScale.Parent = dock

local dockConstraint = Instance.new("UISizeConstraint")
dockConstraint.MinSize = Vector2.new(206, 138)
dockConstraint.MaxSize = Vector2.new(290, 190)
dockConstraint.Parent = dock

local dockTitle = Instance.new("TextLabel")
dockTitle.BackgroundTransparency = 1
dockTitle.Size = UDim2.new(1, -16, 0, 28)
dockTitle.Position = UDim2.fromOffset(8, 6)
dockTitle.Text = "🚨 مركز البلاغات"
dockTitle.Font = Enum.Font.GothamBold
dockTitle.TextSize = 16
dockTitle.TextColor3 = Color3.fromRGB(201, 216, 255)
dockTitle.TextXAlignment = Enum.TextXAlignment.Right
dockTitle.ZIndex = 24
dockTitle.Parent = dock

local citizenButton = Instance.new("TextButton")
citizenButton.Size = UDim2.new(1, -16, 0, 52)
citizenButton.Position = UDim2.fromOffset(8, 38)
citizenButton.BackgroundColor3 = Color3.fromRGB(220, 63, 63)
citizenButton.TextColor3 = Color3.new(1, 1, 1)
citizenButton.Font = Enum.Font.GothamBold
citizenButton.TextSize = 16
citizenButton.Text = "📢 إرسال بلاغ"
citizenButton.ZIndex = 24
citizenButton.Parent = dock
createCorner(citizenButton, 12)
animateButton(citizenButton)

local policePanelButton = Instance.new("TextButton")
policePanelButton.Size = UDim2.new(1, -16, 0, 52)
policePanelButton.Position = UDim2.fromOffset(8, 100)
policePanelButton.BackgroundColor3 = Color3.fromRGB(49, 109, 230)
policePanelButton.TextColor3 = Color3.new(1, 1, 1)
policePanelButton.Font = Enum.Font.GothamBold
policePanelButton.TextSize = 16
policePanelButton.Text = "🚓 لوحة الشرطة"
policePanelButton.ZIndex = 24
policePanelButton.Parent = dock
createCorner(policePanelButton, 12)
animateButton(policePanelButton)

-- Citizen modal
local citizenModal = Instance.new("Frame")
citizenModal.AnchorPoint = Vector2.new(0.5, 0.5)
citizenModal.Position = UDim2.fromScale(0.5, 0.5)
citizenModal.Size = UDim2.fromScale(0.9, 0.72)
citizenModal.BackgroundColor3 = Color3.fromRGB(16, 22, 38)
citizenModal.BorderSizePixel = 0
citizenModal.Visible = false
citizenModal.ZIndex = 30
citizenModal.Parent = safeArea
createCorner(citizenModal, 16)
addStroke(citizenModal, Color3.fromRGB(102, 126, 190), 1, 0.35)
addGradient(citizenModal, {Color3.fromRGB(18, 26, 44), Color3.fromRGB(14, 19, 33)}, 40)

local citizenConstraint = Instance.new("UISizeConstraint")
citizenConstraint.MinSize = Vector2.new(320, 260)
citizenConstraint.MaxSize = Vector2.new(720, 520)
citizenConstraint.Parent = citizenModal

local citizenTitle = Instance.new("TextLabel")
citizenTitle.BackgroundTransparency = 1
citizenTitle.Size = UDim2.new(1, -20, 0, 36)
citizenTitle.Position = UDim2.fromOffset(10, 10)
citizenTitle.Text = "إرسال بلاغ جديد"
citizenTitle.TextXAlignment = Enum.TextXAlignment.Right
citizenTitle.Font = Enum.Font.GothamBold
citizenTitle.TextSize = 26
citizenTitle.TextColor3 = Color3.fromRGB(255, 111, 111)
citizenTitle.ZIndex = 32
citizenTitle.Parent = citizenModal

local suspectLabel = Instance.new("TextLabel")
suspectLabel.BackgroundTransparency = 1
suspectLabel.Size = UDim2.new(1, -24, 0, 22)
suspectLabel.Position = UDim2.fromOffset(12, 54)
suspectLabel.Text = "اسم الشخص المبلّغ عنه"
suspectLabel.TextXAlignment = Enum.TextXAlignment.Right
suspectLabel.Font = Enum.Font.GothamSemibold
suspectLabel.TextSize = 14
suspectLabel.TextColor3 = Color3.fromRGB(205, 220, 255)
suspectLabel.ZIndex = 32
suspectLabel.Parent = citizenModal

local suspectBox = Instance.new("TextBox")
suspectBox.Size = UDim2.new(1, -24, 0, 42)
suspectBox.Position = UDim2.fromOffset(12, 78)
suspectBox.BackgroundColor3 = Color3.fromRGB(30, 38, 61)
suspectBox.TextColor3 = Color3.fromRGB(245, 248, 255)
suspectBox.PlaceholderText = "مثال: Ahmed123"
suspectBox.ClearTextOnFocus = false
suspectBox.TextXAlignment = Enum.TextXAlignment.Right
suspectBox.Font = Enum.Font.GothamSemibold
suspectBox.TextSize = 16
suspectBox.ZIndex = 32
suspectBox.Parent = citizenModal
createCorner(suspectBox, 10)
addStroke(suspectBox, Color3.fromRGB(110, 131, 194), 1, 0.45)

local reasonLabel = Instance.new("TextLabel")
reasonLabel.BackgroundTransparency = 1
reasonLabel.Size = UDim2.new(1, -24, 0, 22)
reasonLabel.Position = UDim2.fromOffset(12, 128)
reasonLabel.Text = "سبب البلاغ"
reasonLabel.TextXAlignment = Enum.TextXAlignment.Right
reasonLabel.Font = Enum.Font.GothamSemibold
reasonLabel.TextSize = 14
reasonLabel.TextColor3 = Color3.fromRGB(205, 220, 255)
reasonLabel.ZIndex = 32
reasonLabel.Parent = citizenModal

local reasonBox = Instance.new("TextBox")
reasonBox.Size = UDim2.new(1, -24, 1, -238)
reasonBox.Position = UDim2.fromOffset(12, 152)
reasonBox.BackgroundColor3 = Color3.fromRGB(30, 38, 61)
reasonBox.TextColor3 = Color3.fromRGB(245, 248, 255)
reasonBox.PlaceholderText = "اكتب سبب البلاغ بالتفصيل..."
reasonBox.ClearTextOnFocus = false
reasonBox.MultiLine = true
reasonBox.TextWrapped = true
reasonBox.TextXAlignment = Enum.TextXAlignment.Right
reasonBox.TextYAlignment = Enum.TextYAlignment.Top
reasonBox.Font = Enum.Font.GothamSemibold
reasonBox.TextSize = 15
reasonBox.ZIndex = 32
reasonBox.Parent = citizenModal
createCorner(reasonBox, 10)
addStroke(reasonBox, Color3.fromRGB(110, 131, 194), 1, 0.45)

local citizenClose = Instance.new("TextButton")
citizenClose.Size = UDim2.fromOffset(130, 42)
citizenClose.Position = UDim2.new(1, -274, 1, -54)
citizenClose.BackgroundColor3 = Color3.fromRGB(72, 83, 109)
citizenClose.TextColor3 = Color3.new(1, 1, 1)
citizenClose.Text = "إغلاق"
citizenClose.Font = Enum.Font.GothamBold
citizenClose.TextSize = 16
citizenClose.ZIndex = 33
citizenClose.Parent = citizenModal
createCorner(citizenClose, 10)
animateButton(citizenClose)

local citizenSend = Instance.new("TextButton")
citizenSend.Size = UDim2.fromOffset(130, 42)
citizenSend.Position = UDim2.new(1, -136, 1, -54)
citizenSend.BackgroundColor3 = Color3.fromRGB(223, 64, 64)
citizenSend.TextColor3 = Color3.new(1, 1, 1)
citizenSend.Text = "إرسال"
citizenSend.Font = Enum.Font.GothamBold
citizenSend.TextSize = 16
citizenSend.ZIndex = 33
citizenSend.Parent = citizenModal
createCorner(citizenSend, 10)
animateButton(citizenSend)

-- Police modal
local policeModal = Instance.new("Frame")
policeModal.AnchorPoint = Vector2.new(0.5, 0.5)
policeModal.Position = UDim2.fromScale(0.5, 0.5)
policeModal.Size = UDim2.fromScale(0.94, 0.82)
policeModal.BackgroundColor3 = Color3.fromRGB(14, 20, 35)
policeModal.BorderSizePixel = 0
policeModal.Visible = false
policeModal.ZIndex = 30
policeModal.Parent = safeArea
createCorner(policeModal, 16)
addStroke(policeModal, Color3.fromRGB(91, 128, 209), 1, 0.3)
addGradient(policeModal, {Color3.fromRGB(18, 27, 46), Color3.fromRGB(13, 19, 31)}, 30)

local policeConstraint = Instance.new("UISizeConstraint")
policeConstraint.MinSize = Vector2.new(360, 280)
policeConstraint.MaxSize = Vector2.new(980, 700)
policeConstraint.Parent = policeModal

local policeTitle = Instance.new("TextLabel")
policeTitle.BackgroundTransparency = 1
policeTitle.Size = UDim2.new(1, -24, 0, 36)
policeTitle.Position = UDim2.fromOffset(12, 10)
policeTitle.Text = "لوحة بلاغات الشرطة"
policeTitle.TextXAlignment = Enum.TextXAlignment.Right
policeTitle.Font = Enum.Font.GothamBold
policeTitle.TextSize = 26
policeTitle.TextColor3 = Color3.fromRGB(121, 189, 255)
policeTitle.ZIndex = 32
policeTitle.Parent = policeModal

local policeClose = Instance.new("TextButton")
policeClose.Size = UDim2.fromOffset(120, 36)
policeClose.Position = UDim2.new(1, -132, 0, 12)
policeClose.BackgroundColor3 = Color3.fromRGB(71, 83, 108)
policeClose.TextColor3 = Color3.new(1, 1, 1)
policeClose.Text = "إغلاق"
policeClose.Font = Enum.Font.GothamBold
policeClose.TextSize = 14
policeClose.ZIndex = 33
policeClose.Parent = policeModal
createCorner(policeClose, 10)
animateButton(policeClose)

local policeRefresh = Instance.new("TextButton")
policeRefresh.Size = UDim2.fromOffset(120, 36)
policeRefresh.Position = UDim2.new(1, -260, 0, 12)
policeRefresh.BackgroundColor3 = Color3.fromRGB(49, 109, 230)
policeRefresh.TextColor3 = Color3.new(1, 1, 1)
policeRefresh.Text = "تحديث"
policeRefresh.Font = Enum.Font.GothamBold
policeRefresh.TextSize = 14
policeRefresh.ZIndex = 33
policeRefresh.Parent = policeModal
createCorner(policeRefresh, 10)
animateButton(policeRefresh)

local policeList = Instance.new("ScrollingFrame")
policeList.Size = UDim2.new(1, -24, 1, -66)
policeList.Position = UDim2.fromOffset(12, 54)
policeList.BackgroundColor3 = Color3.fromRGB(24, 33, 55)
policeList.BorderSizePixel = 0
policeList.ScrollBarThickness = 8
policeList.CanvasSize = UDim2.fromOffset(0, 0)
policeList.ZIndex = 32
policeList.Parent = policeModal
createCorner(policeList, 12)
addStroke(policeList, Color3.fromRGB(93, 127, 201), 1, 0.55)

local policeListLayout = Instance.new("UIListLayout")
policeListLayout.Padding = UDim.new(0, 10)
policeListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
policeListLayout.Parent = policeList

local emptyState = Instance.new("TextLabel")
emptyState.BackgroundTransparency = 1
emptyState.Size = UDim2.new(1, -30, 0, 36)
emptyState.Position = UDim2.fromOffset(15, 86)
emptyState.Text = "لا يوجد بلاغات حالياً"
emptyState.TextXAlignment = Enum.TextXAlignment.Center
emptyState.Font = Enum.Font.GothamSemibold
emptyState.TextSize = 20
emptyState.TextColor3 = Color3.fromRGB(173, 194, 237)
emptyState.Visible = false
emptyState.ZIndex = 33
emptyState.Parent = policeModal

local function rebuildPoliceList()
    for _, child in ipairs(policeList:GetChildren()) do
        if child:IsA("Frame") then
            child:Destroy()
        end
    end

    local rows: {PendingReport} = {}
    for _, report in pairs(pendingReports) do
        table.insert(rows, report)
    end
    table.sort(rows, function(a, b)
        return a.createdAt > b.createdAt
    end)

    emptyState.Visible = #rows == 0

    for _, report in ipairs(rows) do
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, -18, 0, 122)
        row.BackgroundColor3 = Color3.fromRGB(28, 38, 62)
        row.BorderSizePixel = 0
        row.ZIndex = 34
        row.Parent = policeList
        createCorner(row, 12)
        addStroke(row, Color3.fromRGB(102, 135, 205), 1, 0.6)

        local header = Instance.new("TextLabel")
        header.BackgroundTransparency = 1
        header.Size = UDim2.new(1, -16, 0, 24)
        header.Position = UDim2.fromOffset(8, 6)
        header.Text = string.format("📩 %s", formatTimeAgo(report.createdAt))
        header.TextXAlignment = Enum.TextXAlignment.Right
        header.Font = Enum.Font.GothamBold
        header.TextSize = 13
        header.TextColor3 = Color3.fromRGB(154, 189, 255)
        header.ZIndex = 35
        header.Parent = row

        local info = Instance.new("TextLabel")
        info.BackgroundTransparency = 1
        info.Size = UDim2.new(1, -188, 1, -38)
        info.Position = UDim2.fromOffset(8, 30)
        info.TextXAlignment = Enum.TextXAlignment.Right
        info.TextYAlignment = Enum.TextYAlignment.Top
        info.TextWrapped = true
        info.Font = Enum.Font.GothamSemibold
        info.TextSize = 14
        info.TextColor3 = Color3.fromRGB(232, 239, 255)
        info.Text = string.format("المواطن: %s\nالمبلّغ عنه: %s\nالسبب: %s", report.reporterName, report.suspectName, report.reason)
        info.ZIndex = 35
        info.Parent = row

        local accept = Instance.new("TextButton")
        accept.Size = UDim2.fromOffset(78, 34)
        accept.Position = UDim2.new(1, -170, 0.5, -17)
        accept.BackgroundColor3 = Color3.fromRGB(44, 186, 99)
        accept.TextColor3 = Color3.new(1, 1, 1)
        accept.Text = "قبول"
        accept.Font = Enum.Font.GothamBold
        accept.TextSize = 14
        accept.ZIndex = 35
        accept.Parent = row
        createCorner(accept, 9)
        animateButton(accept)

        local reject = Instance.new("TextButton")
        reject.Size = UDim2.fromOffset(78, 34)
        reject.Position = UDim2.new(1, -84, 0.5, -17)
        reject.BackgroundColor3 = Color3.fromRGB(205, 66, 66)
        reject.TextColor3 = Color3.new(1, 1, 1)
        reject.Text = "رفض"
        reject.Font = Enum.Font.GothamBold
        reject.TextSize = 14
        reject.ZIndex = 35
        reject.Parent = row
        createCorner(reject, 9)
        animateButton(reject)

        accept.MouseButton1Click:Connect(function()
            reviewReport:FireServer({ reportId = report.reportId, approve = true })
        end)

        reject.MouseButton1Click:Connect(function()
            reviewReport:FireServer({ reportId = report.reportId, approve = false })
        end)
    end

    policeList.CanvasSize = UDim2.fromOffset(0, policeListLayout.AbsoluteContentSize.Y + 16)
end

local function loadPendingReportsFromServer()
    local ok, result = pcall(function()
        return getPendingReports:InvokeServer()
    end)

    if not ok or typeof(result) ~= "table" then
        showFancyNotification("خطأ", "تعذر تحميل البلاغات الآن.")
        return
    end

    pendingReports = {}
    for _, row in ipairs(result :: {any}) do
        if typeof(row) == "table" then
            local reportId = tostring(row.reportId or "")
            if reportId ~= "" then
                pendingReports[reportId] = {
                    reportId = reportId,
                    reporterName = tostring(row.reporterName or "Unknown"),
                    suspectName = tostring(row.suspectName or "غير محدد"),
                    reason = tostring(row.reason or ""),
                    createdAt = tonumber(row.createdAt) or 0,
                }
            end
        end
    end
end

local function updatePoliceButtonVisibility()
    policePanelButton.Visible = isPoliceLocal()
end

-- Responsiveness tuning for phones/tablets
local function updateResponsiveLayout()
    local camera = workspace.CurrentCamera
    local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)

    if viewport.X < 800 then
        dockScale.Scale = 0.85
        dock.Position = UDim2.new(0, 8, 0.5, 0)
        dock.Size = UDim2.fromOffset(222, 150)
        dockTitle.TextSize = 14
        citizenButton.TextSize = 14
        policePanelButton.TextSize = 14
    elseif viewport.X < 1200 then
        dockScale.Scale = 0.95
        dock.Position = UDim2.new(0, 10, 0.5, 0)
        dock.Size = UDim2.fromOffset(236, 154)
        dockTitle.TextSize = 15
        citizenButton.TextSize = 15
        policePanelButton.TextSize = 15
    else
        dockScale.Scale = 1
        dock.Position = UDim2.new(0, 14, 0.5, 0)
        dock.Size = UDim2.fromOffset(250, 160)
        dockTitle.TextSize = 16
        citizenButton.TextSize = 16
        policePanelButton.TextSize = 16
    end
end

citizenButton.MouseButton1Click:Connect(function()
    openModal(citizenModal)
end)

citizenClose.MouseButton1Click:Connect(function()
    closeModal(citizenModal)
end)

citizenSend.MouseButton1Click:Connect(function()
    submitReport:FireServer({
        suspectName = suspectBox.Text,
        reason = reasonBox.Text,
    })

    suspectBox.Text = ""
    reasonBox.Text = ""
    closeModal(citizenModal)
end)

policePanelButton.MouseButton1Click:Connect(function()
    if not isPoliceLocal() then
        showFancyNotification("غير مصرح", "هذه اللوحة لفريق الشرطة فقط.")
        return
    end

    loadPendingReportsFromServer()
    rebuildPoliceList()
    openModal(policeModal)
end)

policeClose.MouseButton1Click:Connect(function()
    closeModal(policeModal)
end)

policeRefresh.MouseButton1Click:Connect(function()
    loadPendingReportsFromServer()
    rebuildPoliceList()
    showFancyNotification("تم التحديث", "تم تحديث قائمة البلاغات.")
end)

reportStatusUpdate.OnClientEvent:Connect(function(payload)
    if typeof(payload) ~= "table" then
        return
    end

    showFancyNotification(tostring(payload.title or "إشعار"), tostring(payload.text or ""))
end)

reportApprovedNotify.OnClientEvent:Connect(function(payload)
    if typeof(payload) ~= "table" then
        return
    end

    local targetPosition = payload.position
    if typeof(targetPosition) ~= "Vector3" then
        return
    end

    local reporterName = tostring(payload.reporterName or "غير معروف")
    local suspectName = tostring(payload.suspectName or "غير محدد")
    showFancyNotification(
        "بلاغ معتمد",
        string.format("المواطن: %s | المبلّغ عنه: %s\nتم تفعيل التوجيه للموقع.", reporterName, suspectName)
    )

    setupGuidance(targetPosition)
end)

policeInboxUpdate.OnClientEvent:Connect(function(payload)
    if typeof(payload) ~= "table" then
        return
    end

    local action = tostring(payload.action or "")
    local reportId = tostring(payload.reportId or "")
    if reportId == "" then
        return
    end

    if action == "remove" then
        pendingReports[reportId] = nil
    elseif action == "add" then
        pendingReports[reportId] = {
            reportId = reportId,
            reporterName = tostring(payload.reporterName or "Unknown"),
            suspectName = tostring(payload.suspectName or "غير محدد"),
            reason = tostring(payload.reason or ""),
            createdAt = tonumber(payload.createdAt) or os.time(),
        }
    end

    if policeModal.Visible then
        rebuildPoliceList()
    end
end)

player:GetPropertyChangedSignal("Team"):Connect(updatePoliceButtonVisibility)
updatePoliceButtonVisibility()

local function bindCameraViewportListener()
    if viewportConnection then
        viewportConnection:Disconnect()
        viewportConnection = nil
    end

    local camera = workspace.CurrentCamera
    if camera then
        viewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateResponsiveLayout)
    end
end

workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
    bindCameraViewportListener()
    updateResponsiveLayout()
end)

bindCameraViewportListener()
updateResponsiveLayout()
