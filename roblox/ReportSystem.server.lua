--!strict
-- Roblox Police Report System (Server)
-- Place in ServerScriptService

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local POLICE_TEAM_NAME = "Police"
local MAX_ACTIVE_REPORTS = 3
local MAX_REASON_LENGTH = 180
local MAX_NAME_LENGTH = 40

local remotesFolder = ReplicatedStorage:FindFirstChild("ReportRemotes")
if not remotesFolder then
    remotesFolder = Instance.new("Folder")
    remotesFolder.Name = "ReportRemotes"
    remotesFolder.Parent = ReplicatedStorage
end

local function ensureRemoteEvent(name: string): RemoteEvent
    local instance = remotesFolder:FindFirstChild(name)
    if instance and instance:IsA("RemoteEvent") then
        return instance
    end

    local created = Instance.new("RemoteEvent")
    created.Name = name
    created.Parent = remotesFolder
    return created
end

local function ensureRemoteFunction(name: string): RemoteFunction
    local instance = remotesFolder:FindFirstChild(name)
    if instance and instance:IsA("RemoteFunction") then
        return instance
    end

    local created = Instance.new("RemoteFunction")
    created.Name = name
    created.Parent = remotesFolder
    return created
end

local submitReport = ensureRemoteEvent("SubmitReport")
local reviewReport = ensureRemoteEvent("ReviewReport")
local reportApprovedNotify = ensureRemoteEvent("ReportApprovedNotify")
local reportStatusUpdate = ensureRemoteEvent("ReportStatusUpdate")
local policeInboxUpdate = ensureRemoteEvent("PoliceInboxUpdate")
local getPendingReports = ensureRemoteFunction("GetPendingReports")

type ReportStatus = "Pending" | "Approved" | "Rejected"

type ReportData = {
    id: string,
    reporterUserId: number,
    reporterName: string,
    suspectName: string,
    reason: string,
    position: Vector3,
    status: ReportStatus,
    createdAt: number,
    approvedByUserId: number?,
}

local activeReports: {[string]: ReportData} = {}
local pendingByReporter: {[number]: {string}} = {}

local function isPolice(player: Player): boolean
    return player.Team ~= nil and player.Team.Name == POLICE_TEAM_NAME
end

local function sanitizeText(raw: any, maxLen: number): string
    local value = tostring(raw or "")
    value = value:gsub("^%s+", ""):gsub("%s+$", "")
    return value:sub(1, maxLen)
end

local function notify(player: Player, title: string, text: string)
    reportStatusUpdate:FireClient(player, {
        title = title,
        text = text,
        timestamp = os.clock(),
    })
end

local function cleanupReporterQueue(userId: number)
    local queue = pendingByReporter[userId]
    if not queue then
        return
    end

    local filtered: {string} = {}
    for _, reportId in ipairs(queue) do
        local report = activeReports[reportId]
        if report and report.status == "Pending" then
            table.insert(filtered, reportId)
        end
    end

    pendingByReporter[userId] = filtered
end

type PendingRow = {
    reportId: string,
    reporterName: string,
    suspectName: string,
    reason: string,
    createdAt: number,
    action: string?,
}

local function toPendingRow(report: ReportData): PendingRow
    return {
        reportId = report.id,
        reporterName = report.reporterName,
        suspectName = report.suspectName,
        reason = report.reason,
        createdAt = report.createdAt,
    }
end

local function buildPendingListForPolice(): {PendingRow}
    local rows: {PendingRow} = {}
    for _, report in pairs(activeReports) do
        if report.status == "Pending" then
            table.insert(rows, toPendingRow(report))
        end
    end

    table.sort(rows, function(a, b)
        return (a.createdAt or 0) > (b.createdAt or 0)
    end)

    return rows
end

local function broadcastInboxAdd(report: ReportData)
    local payload = toPendingRow(report)
    payload.action = "add"

    for _, officer in ipairs(Players:GetPlayers()) do
        if isPolice(officer) then
            policeInboxUpdate:FireClient(officer, payload)
        end
    end
end

local function broadcastInboxRemove(reportId: string)
    for _, officer in ipairs(Players:GetPlayers()) do
        if isPolice(officer) then
            policeInboxUpdate:FireClient(officer, {
                action = "remove",
                reportId = reportId,
            })
        end
    end
end

submitReport.OnServerEvent:Connect(function(player: Player, payload)
    if typeof(payload) ~= "table" then
        return
    end

    local reason = sanitizeText(payload.reason, MAX_REASON_LENGTH)
    local suspectName = sanitizeText(payload.suspectName, MAX_NAME_LENGTH)

    if #reason < 3 then
        notify(player, "البلاغ مرفوض", "اكتب سبب واضح (3 أحرف على الأقل).")
        return
    end

    if #suspectName < 2 then
        notify(player, "البلاغ مرفوض", "اكتب اسم الشخص المبلّغ عنه.")
        return
    end

    cleanupReporterQueue(player.UserId)
    local queue: {string} = pendingByReporter[player.UserId] or {}
    if #queue >= MAX_ACTIVE_REPORTS then
        notify(player, "تم الوصول للحد", "عندك بلاغات كثيرة قيد الانتظار. انتظر المراجعة.")
        return
    end

    local character = player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not root or not root:IsA("BasePart") then
        notify(player, "تعذر الإرسال", "لا يمكن قراءة موقعك الآن.")
        return
    end

    local reportId = string.format("R-%d-%d", player.UserId, math.floor(os.clock() * 1000))
    local report: ReportData = {
        id = reportId,
        reporterUserId = player.UserId,
        reporterName = player.Name,
        suspectName = suspectName,
        reason = reason,
        position = root.Position,
        status = "Pending",
        createdAt = os.time(),
    }

    activeReports[reportId] = report
    table.insert(queue, reportId)
    pendingByReporter[player.UserId] = queue

    notify(player, "تم إرسال البلاغ", "البلاغ وصل للشرطة وبانتظار الموافقة.")
    broadcastInboxAdd(report)

    for _, officer in ipairs(Players:GetPlayers()) do
        if isPolice(officer) then
            notify(
                officer,
                "بلاغ جديد",
                string.format("المواطن: %s | المبلّغ عنه: %s", report.reporterName, report.suspectName)
            )
        end
    end
end)

reviewReport.OnServerEvent:Connect(function(player: Player, payload)
    if not isPolice(player) then
        return
    end

    if typeof(payload) ~= "table" then
        return
    end

    local reportId = tostring(payload.reportId or "")
    local approve = payload.approve == true

    if reportId == "" then
        return
    end

    local report = activeReports[reportId]
    if not report or report.status ~= "Pending" then
        notify(player, "بلاغ غير متاح", "البلاغ غير موجود أو تمت مراجعته.")
        return
    end

    if approve then
        report.status = "Approved"
        report.approvedByUserId = player.UserId

        reportApprovedNotify:FireClient(player, {
            reportId = report.id,
            reporterName = report.reporterName,
            suspectName = report.suspectName,
            reason = report.reason,
            position = report.position,
        })

        local reporter = Players:GetPlayerByUserId(report.reporterUserId)
        if reporter then
            notify(reporter, "تم قبول بلاغك", "تم توجيه أقرب دورية نحو موقعك.")
        end

        notify(player, "تم القبول", "ظهر لك الموقع بسهم + خط أحمر.")
    else
        report.status = "Rejected"

        local reporter = Players:GetPlayerByUserId(report.reporterUserId)
        if reporter then
            notify(reporter, "تم رفض البلاغ", "يرجى توضيح أكثر ثم أعد الإرسال.")
        end

        notify(player, "تم الرفض", "تم إغلاق البلاغ.")
    end

    broadcastInboxRemove(report.id)
    cleanupReporterQueue(report.reporterUserId)
end)

getPendingReports.OnServerInvoke = function(player: Player)
    if not isPolice(player) then
        return {}
    end

    return buildPendingListForPolice()
end

Players.PlayerRemoving:Connect(function(player: Player)
    pendingByReporter[player.UserId] = nil
end)
