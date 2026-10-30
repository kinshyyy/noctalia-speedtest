local activeResult = nil
local resultExpiresAt = 0
local seenMetricsAt = 0
local lastGlyph = nil
local lastText = nil
local lastTooltip = nil

local function roundedMetric(value)
    local number = tonumber(value)
    if not number then return nil end
    return math.floor(number + 0.5)
end

local function captureLatestResult()
    local updatedAt = tonumber(noctalia.state.get("last_metrics_at")) or 0
    if updatedAt <= 0 or updatedAt == seenMetricsAt then return end
    seenMetricsAt = updatedAt

    -- The temporary result has its own toggle; it must work even when the
    -- persistent label is disabled or the setting has not been saved yet.
    if noctalia.getConfig("show_result_on_bar") == false then return end
    local metrics = noctalia.state.get("last_metrics")
    if type(metrics) ~= "table" then return end

    local download = roundedMetric(metrics.download)
    local upload = roundedMetric(metrics.upload)
    if not download or not upload then return end

    local duration = tonumber(noctalia.getConfig("result_duration")) or 10
    resultExpiresAt = updatedAt + math.clamp(duration, 1, 120) * 1000
    if noctalia.nowMs() >= resultExpiresAt then return end

    activeResult = string.format("↓%d ↑%d Mbps", download, upload)
end

noctalia.setUpdateInterval(250)

function update()
    local glyph = noctalia.getConfig("glyph") or "activity"
    if glyph ~= lastGlyph then
        barWidget.setGlyph(glyph)
        lastGlyph = glyph
    end

    captureLatestResult()
    local now = noctalia.nowMs()
    local showResult = noctalia.getConfig("show_result_on_bar") ~= false
    local text
    local tooltip
    if showResult and activeResult and now < resultExpiresAt then
        text = activeResult
        local metrics = noctalia.state.get("last_metrics") or {}
        tooltip = string.format(
            "Download: %s Mbps · Upload: %s Mbps · Ping: %s ms",
            tostring(roundedMetric(metrics.download) or "—"),
            tostring(roundedMetric(metrics.upload) or "—"),
            tostring(roundedMetric(metrics.latency) or "—")
        )
    else
        activeResult = nil
        text = noctalia.getConfig("show_label") == false and "" or "SpeedTest"
        tooltip = "Abrir o teste de velocidade"
    end

    if text ~= lastText then
        barWidget.setText(text)
        lastText = text
    end
    if tooltip ~= lastTooltip then
        barWidget.setTooltip(tooltip)
        lastTooltip = tooltip
    end
end

function onClick()
    noctalia.togglePanel("vinicius/speedtest:panel")
end
