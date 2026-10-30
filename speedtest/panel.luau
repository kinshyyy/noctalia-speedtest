--!nonstrict

local running = false
local panelOpen = false
local statusText = "Pronto para testar"
local outputText = ""
local showOutput = false
local outputMode = ""
local historyGeneration = 0
local watchEnabled = false
local gaugePaths = { download = nil, upload = nil }
local gaugeSequence = 0
local gaugeFiles = {}
local animationStage = nil
local pendingAnimationStage = nil
local animationElapsed = 0
local animationFrameElapsed = 0
local metrics = { download = "--", upload = "--", latency = "--", quality = "—" }

local function scriptPath()
    return (noctalia.pluginDir() or ".") .. "/speedtest.sh"
end

local function cleanOutput(text)
    text = tostring(text or "")
    text = string.gsub(text, "\27%[[0-9;?]*[ -/]*[@-~]", "")
    text = string.gsub(text, "\r", "\n")
    text = string.gsub(text, "\n\n\n+", "\n\n")
    return noctalia.string.trim(text)
end

local function parseMetric(text, label)
    local value = string.match(text, label .. ":%s*([%d%.]+)%s*[%a%%]*")
    return value or "--"
end

local function parseResult(text)
    local markerStart = string.find(text, "SPEEDTEST_RESULT|", 1, true)
    if markerStart then
        local markerLine = string.match(string.sub(text, markerStart), "^([^\n]+)")
        local parts = string.split(markerLine or "", "|")
        if #parts >= 5 then
            return { download = parts[2], upload = parts[3], latency = parts[4], quality = parts[5] }
        end
    end
    local download, upload, latency, quality = string.match(text, "SPEEDTEST_RESULT|([^|\n]+)|([^|\n]+)|([^|\n]+)|([^|\n]+)")
    if download then
        return { download = download, upload = upload, latency = latency, quality = quality }
    end
    download = parseMetric(text, "Download")
    upload = parseMetric(text, "Upload")
    latency = parseMetric(text, "Latência")
    if latency == "--" then latency = parseMetric(text, "Latency") end
    if download == "--" or upload == "--" or latency == "--" then return nil end
    local q = string.match(text, "Qualidade da conexão:%s*([^\n]+)") or "—"
    return { download = download, upload = upload, latency = latency, quality = q }
end

local function notifyResult(value)
    if noctalia.getConfig("notify_result") == false then return end
    local download = tonumber(value.download)
    local upload = tonumber(value.upload)
    local latency = tonumber(value.latency)
    if not download or not upload or not latency then return end
    noctalia.notify(
        "SpeedTest concluído",
        string.format("Download: %d Mbps · Upload: %d Mbps · Ping: %d ms", math.floor(download + 0.5), math.floor(upload + 0.5), math.floor(latency + 0.5))
    )
end

local gaugeTicks = {
    { speed = 0, ratio = 0.00 },
    { speed = 5, ratio = 0.05 },
    { speed = 10, ratio = 0.10 },
    { speed = 50, ratio = 0.24 },
    { speed = 100, ratio = 0.39 },
    { speed = 250, ratio = 0.56 },
    { speed = 500, ratio = 0.72 },
    { speed = 750, ratio = 0.87 },
    { speed = 1000, ratio = 1.00 },
}

local function speedToRatio(value)
    local speed = math.max(0, tonumber(value) or 0)
    for i = 2, #gaugeTicks do
        local previous = gaugeTicks[i - 1]
        local current = gaugeTicks[i]
        if speed <= current.speed then
            local localRatio = (speed - previous.speed) / (current.speed - previous.speed)
            return previous.ratio + localRatio * (current.ratio - previous.ratio)
        end
    end
    return 1
end

local function writeGauge(kind, value, active, sweep)
    local numeric = tonumber(value) or 0
    local ratio = active and math.clamp(sweep or 0, 0.02, 0.98) or speedToRatio(numeric)
    -- O arco vai de 150° a 390°; o ponteiro usa a mesma escala do mostrador.
    local angle = math.rad(150 + ratio * 240)
    local needleX = 150 + math.cos(angle) * 75
    local needleY = 135 + math.sin(angle) * 75
    local accent = kind == "download"
        and (noctalia.getColor("primary") or "#31C6F4")
        or (noctalia.getColor("secondary") or "#FFB398")
    local arcLength = 439.8 -- raio de 105 px × 240 graus.
    local arc = string.format("%.1f %.1f", ratio * arcLength, arcLength)
    local tickLabels = {}
    for _, tick in ipairs(gaugeTicks) do
        local tickAngle = math.rad(150 + tick.ratio * 240)
        local x = 150 + math.cos(tickAngle) * 86
        local y = 135 + math.sin(tickAngle) * 86
        table.insert(tickLabels, string.format('<text x="%.1f" y="%.1f" text-anchor="middle" class="tick">%d</text>', x, y, tick.speed))
    end
    local shownValue = numeric > 0 and string.format("%.0f", numeric) or (active and "--" or "—")
    local unitText = "Mbps"
    local svg = string.format([[
<svg xmlns="http://www.w3.org/2000/svg" width="300" height="210" viewBox="0 0 300 210">
  <defs><linearGradient id="arc" x1="0" y1="1" x2="1" y2="0"><stop offset="0%%" stop-color="%s"/><stop offset="100%%" stop-color="%s"/></linearGradient></defs>
  <text x="150" y="17" text-anchor="middle" class="title">%s</text>
  <path d="M59 187 A105 105 0 1 1 241 187" fill="none" stroke="#343443" stroke-width="13" stroke-linecap="round"/>
  <path d="M59 187 A105 105 0 1 1 241 187" fill="none" stroke="url(#arc)" stroke-width="13" stroke-linecap="round" stroke-dasharray="%s"/>
  %s
  <line x1="150" y1="135" x2="%.1f" y2="%.1f" stroke="#F7F4F1" stroke-width="4" stroke-linecap="round"/>
  <circle cx="150" cy="135" r="7" fill="%s" stroke="#F7F4F1" stroke-width="2"/>
  <text x="150" y="171" text-anchor="middle" class="speed">%s</text>
  <text x="150" y="190" text-anchor="middle" class="unit">%s</text>
  <style>.title{font:600 14px sans-serif;fill:#f7f4f1;letter-spacing:1px}.tick{font:600 10px sans-serif;fill:#aaaab5}.speed{font:500 25px sans-serif;fill:#f7f4f1}.unit{font:13px sans-serif;fill:#aaaab5;letter-spacing:0;text-anchor:middle}</style>
</svg>]], accent, accent, string.upper(kind), arc, table.concat(tickLabels, "\n  "), needleX, needleY, accent, shownValue, unitText)

    local dir = noctalia.pluginDataDir()
    if not dir then return nil end
    gaugeSequence += 1
    local path = dir .. "/speedtest-gauge-" .. tostring(gaugeSequence) .. ".svg"
    local ok = noctalia.writeFile(path, svg)
    if ok then
        gaugePaths[kind] = path
        table.insert(gaugeFiles, path)
        if #gaugeFiles > 24 then
            local oldPath = table.remove(gaugeFiles, 1)
            noctalia.removeFile(oldPath)
        end
    end
    return gaugePaths[kind]
end

local function createGauges(activeMode, sweep)
    writeGauge("download", metrics.download, activeMode == "download", sweep)
    writeGauge("upload", metrics.upload, activeMode == "upload", sweep)
end

local function configArgs()
    local args = {}
    local server = tostring(noctalia.getConfig("server_id") or "")
    local historyDir = tostring(noctalia.getConfig("history_dir") or "")
    if server ~= "" then
        table.insert(args, "--server")
        table.insert(args, server)
    end
    if noctalia.getConfig("show_provider") == true then table.insert(args, "--show-ip") end
    if noctalia.getConfig("save_history") == false then
        table.insert(args, "--no-history")
    elseif historyDir ~= "" then
        table.insert(args, "--history")
        table.insert(args, noctalia.expandPath(historyDir))
    end
    return args
end

local function shellQuote(value)
    return "'" .. string.gsub(tostring(value), "'", "'\\''") .. "'"
end

local function startTestStream(action, label)
    if running or noctalia.state.get("running") == true then return end
    running = true
    animationStage = "download"
    pendingAnimationStage = nil
    animationElapsed = 0
    animationFrameElapsed = 0
    statusText = "Medindo download…"
    outputText = ""
    showOutput = false
    outputMode = ""
    noctalia.state.set("output_visible", false)
    noctalia.state.set("output_mode", "")
    metrics = { download = "--", upload = "--", latency = "--", quality = "—" }
    noctalia.state.set("running", true)
    createGauges("download", 0.02)
    renderPanel()
    panel.setNeedsFrameTick(true)

    local argv = { "bash", scriptPath(), "--plugin-mode" }
    for _, arg in ipairs(configArgs()) do table.insert(argv, arg) end
    if action == "test-full" then table.insert(argv, "--full") end
    local quoted = {}
    for _, arg in ipairs(argv) do table.insert(quoted, shellQuote(arg)) end
    local command = table.concat(quoted, " ") .. " 2>&1; code=$?; printf '\\nSPEEDTEST_EXIT|%s\\n' \"$code\"; exit \"$code\""
    local gotResult = false

    local accepted = noctalia.runStream(command, function(line)
        line = cleanOutput(line)
        local partialDownload = tonumber(string.match(line, "SPEEDTEST_DOWNLOAD|([%d%.]+)"))
        if partialDownload then
            metrics.download = tostring(partialDownload)
            createGauges(animationStage, 0.5)
            renderPanel()
            return
        end
        local phase = string.match(line, "SPEEDTEST_PHASE|([^|]+)")
        if phase then
            if phase == "upload" and animationStage == "download" and animationElapsed < 1200 then
                pendingAnimationStage = phase
            else
                animationStage = phase
                pendingAnimationStage = nil
                animationElapsed = 0
            end
            statusText = animationStage == "upload" and "Medindo upload…" or "Medindo download…"
            renderPanel()
            return
        end
        local markerStart = string.find(line, "SPEEDTEST_RESULT|", 1, true)
        if markerStart then
            local parsed = parseResult(string.sub(line, markerStart))
            if parsed then
                gotResult = true
                metrics = parsed
                animationStage = nil
                pendingAnimationStage = nil
                panel.setNeedsFrameTick(false)
                createGauges()
                noctalia.state.set("last_metrics", metrics)
                noctalia.state.set("last_metrics_at", noctalia.nowMs())
                renderPanel()
            end
        end
        local exitCode = tonumber(string.match(line, "SPEEDTEST_EXIT|(%d+)"))
        if exitCode ~= nil then
            running = false
            animationStage = nil
            pendingAnimationStage = nil
            panel.setNeedsFrameTick(false)
            noctalia.state.set("running", false)
            if exitCode == 0 and gotResult then
                statusText = label .. " concluído"
                createGauges()
                notifyResult(metrics)
            else
                statusText = exitCode == 0 and "O teste terminou sem fornecer as métricas." or ("Teste falhou (código " .. tostring(exitCode) .. ")")
            end
            noctalia.state.set("last_output", outputText)
            noctalia.state.set("status", statusText)
            renderPanel()
            return
        end
        if line ~= "" then
            outputText ..= (outputText ~= "" and "\n" or "") .. line
            local lines = string.split(outputText, "\n")
            if #lines > 100 then outputText = table.concat(lines, "\n", #lines - 99, #lines) end
            renderPanel()
        end
    end)
    if not accepted then
        running = false
        animationStage = nil
        pendingAnimationStage = nil
        panel.setNeedsFrameTick(false)
        noctalia.state.set("running", false)
        statusText = "Não foi possível iniciar o teste"
        renderPanel()
    end
end

local function startAction(action, label, useConfig)
    if action == "test" or action == "test-full" then
        startTestStream(action, label)
        return
    end
    if running or noctalia.state.get("running") == true then return end
    running = true
    noctalia.state.set("running", true)
    statusText = label .. "…"
    outputText = ""
    showOutput = action == "list" or action == "stats" or action == "clean"
    outputMode = showOutput and action or ""
    if action == "stats" then historyGeneration += 1 end
    noctalia.state.set("output_visible", showOutput)
    noctalia.state.set("output_mode", outputMode)
    renderPanel()

    local argv = { "bash", scriptPath(), "--plugin-mode" }
    if useConfig then
        for _, arg in ipairs(configArgs()) do table.insert(argv, arg) end
    end
    if action == "test-full" then
        table.insert(argv, "--full")
    elseif action == "list" then
        table.insert(argv, "--list")
    elseif action == "stats" then
        table.insert(argv, "--stats")
    elseif action == "clean" then
        table.insert(argv, "--clean")
    end

    local accepted = noctalia.runAsync(argv, function(result)
        running = false
        local stdout = cleanOutput(result.stdout)
        local stderr = cleanOutput(result.stderr)
        outputText = stdout
        if stderr ~= "" then outputText ..= (outputText ~= "" and "\n\n" or "") .. stderr end
        if result.exitCode == 0 then
            statusText = label .. " concluído"
        else
            statusText = label .. " falhou (código " .. tostring(result.exitCode) .. ")"
        end
        if result.timedOut then statusText = label .. " excedeu o tempo limite" end

        if action == "test" or action == "test-full" then
            local parsed = parseResult(outputText)
            if parsed then
                metrics = parsed
                noctalia.state.set("last_metrics", metrics)
                noctalia.state.set("last_metrics_at", noctalia.nowMs())
                createGauges()
                if result.exitCode == 0 and not result.timedOut then notifyResult(metrics) end
            else
                statusText = "Teste terminou, mas não retornou as métricas esperadas"
            end
        end
        noctalia.state.set("running", false)
        noctalia.state.set("last_output", outputText)
        noctalia.state.set("status", statusText)
        renderPanel()
    end)
    if not accepted then
        running = false
        noctalia.state.set("running", false)
        statusText = "Não foi possível iniciar o processo"
        renderPanel()
    end
end

local function toggleHistory()
    if showOutput and outputMode == "stats" then
        showOutput = false
        outputMode = ""
        noctalia.state.set("output_visible", false)
        noctalia.state.set("output_mode", "")
        renderPanel()
        return
    end
    startAction("stats", "Estatísticas", true)
end

local function metricCard(title, value, unit, color)
    local numeric = tonumber(value)
    local displayValue = numeric and string.format("%.0f", numeric) or tostring(value)
    return ui.column({ flexGrow = 1, gap = 2, padding = 9, align = "center", fill = "surface_container_high", radius = 10 }, {
        ui.label({ text = title, fontSize = 11, color = "on_surface_variant" }),
        ui.label({ text = displayValue, fontSize = 16, fontWeight = "bold", color = color }),
        ui.label({ text = unit, fontSize = 10, color = "on_surface_variant" }),
    })
end

function renderPanel()
    watchEnabled = noctalia.state.get("watch_enabled") == true
    local historyView = showOutput and outputMode == "stats"
    local children = {
        ui.row({ align = "center", justify = "space_between" }, {
            ui.column({ gap = 2 }, {
                ui.label({ text = "SPEEDTEST", fontSize = 21, fontWeight = "bold" }),
                ui.label({ text = statusText, fontSize = 12, color = "on_surface_variant" }),
            }),
            ui.row({ gap = 2, align = "center" }, {
                ui.button({ glyph = "chart-bar", variant = "ghost", tooltip = "Mostrar/ocultar estatísticas do histórico", enabled = not running, onClick = toggleHistory }),
                ui.button({ glyph = "trash", variant = "ghost", tooltip = "Limpar histórico antigo", enabled = not running, onClick = function() startAction("clean", "Limpeza", true) end }),
                ui.button({ glyph = watchEnabled and "player-stop" or "repeat", variant = watchEnabled and "primary" or "outline", tooltip = watchEnabled and "Parar watch" or "Iniciar watch", onClick = function()
                    noctalia.state.set("watch_enabled", not watchEnabled)
                    watchEnabled = not watchEnabled
                    renderPanel()
                end }),
                ui.button({ glyph = "server", variant = "ghost", tooltip = "Listar servidores", enabled = not running, onClick = function() startAction("list", "Lista de servidores", false) end }),
                ui.button({ glyph = "settings", variant = "ghost", tooltip = "Configurações", onClick = function() noctalia.openSettings() end }),
            }),
        }),
    }

    if historyView then
        local historyContent = outputText ~= "" and outputText or statusText
        local historyLines = string.split(historyContent, "\n")
        local historyLineCount = math.max(1, #historyLines)
        local historyHeight = math.clamp(historyLineCount * 18 + 24, 110, 450)
        local historyRows = {}
        local firstHistoryKey = "history-line-" .. tostring(historyGeneration) .. "-1"
        for index, line in ipairs(historyLines) do
            table.insert(historyRows, ui.label({
                key = "history-line-" .. tostring(historyGeneration) .. "-" .. tostring(index),
                text = line ~= "" and line or " ",
                fontSize = 11,
                maxLines = 1,
            }))
        end
        table.insert(children, ui.scroll({
            key = "history-scroll-" .. tostring(historyGeneration),
            height = historyHeight,
            gap = 2,
            padding = 10,
            fill = "surface_container_high",
            radius = 10,
            revealKey = firstHistoryKey,
        }, historyRows))
    else
        table.insert(children, ui.row({ gap = 8, paddingH = 70, paddingV = 2, align = "center", justify = "center" }, {
            metricCard("DOWNLOAD", metrics.download, "Mbps", "primary"),
            metricCard("UPLOAD", metrics.upload, "Mbps", "secondary"),
            metricCard("PING", metrics.latency, "ms", "tertiary"),
        }))
        if gaugePaths.download and gaugePaths.upload then
            table.insert(children, 2, ui.row({ justify = "center", align = "center", padding = 2 }, {
                ui.image({ path = gaugePaths.download, width = 320, height = 224, fit = "contain" }),
                ui.image({ path = gaugePaths.upload, width = 320, height = 224, fit = "contain" }),
            }))
        end
        table.insert(children, ui.row({ align = "center", paddingH = 70, paddingV = 2 }, {
            ui.label({ text = "Qualidade da conexão: " .. metrics.quality, fontSize = 12, color = "on_surface_variant" }),
        }))
        table.insert(children, ui.row({ gap = 8, paddingH = 70, paddingV = 2 }, {
            ui.button({ text = "Testar", glyph = "player-play", variant = "primary", flexGrow = 1, enabled = not running, onClick = function() startAction("test", "Teste", true) end }),
            ui.button({ text = "Completo", glyph = "list-details", variant = "secondary", flexGrow = 1, enabled = not running, onClick = function() startAction("test-full", "Teste completo", true) end }),
        }))
        if showOutput and outputText ~= "" then
            table.insert(children, ui.separator({ spacing = 3 }))
            table.insert(children, ui.scroll({ height = 116, gap = 4, padding = 8, fill = "surface_container_high", radius = 10 }, {
                ui.label({ text = outputText, fontSize = 11, maxLines = 100 }),
            }))
        end
    end
    panel.render(ui.column({ gap = 9, padding = 14, fill = "surface_container", radius = 16 }, children))
end

function onOpen()
    panelOpen = true
    outputText = tostring(noctalia.state.get("last_output") or "")
    showOutput = noctalia.state.get("output_visible") == true
    outputMode = tostring(noctalia.state.get("output_mode") or "")
    if outputMode == "stats" then historyGeneration += 1 end
    statusText = tostring(noctalia.state.get("status") or "Pronto para testar")
    watchEnabled = noctalia.state.get("watch_enabled") == true
    local savedMetrics = noctalia.state.get("last_metrics")
    if savedMetrics then
        metrics = savedMetrics
    else
        local parsed = parseResult(outputText)
        if parsed then metrics = parsed end
    end
    createGauges()
    renderPanel()
end

function onClose()
    panelOpen = false
    panel.setNeedsFrameTick(false)
end

function onFrameTick(deltaMs)
    if not animationStage or not running then return end
    animationElapsed += deltaMs
    animationFrameElapsed += deltaMs
    if pendingAnimationStage and animationElapsed >= 1200 then
        animationStage = pendingAnimationStage
        pendingAnimationStage = nil
        animationElapsed = 0
    end
    if animationFrameElapsed < 160 then return end
    animationFrameElapsed = 0
    local sweep = 0.5 + math.sin(animationElapsed / 850) * 0.46
    createGauges(animationStage, sweep)
    statusText = animationStage == "upload" and "Medindo upload…" or "Medindo download…"
    renderPanel()
end

noctalia.state.watch("last_output", function(value)
    if value ~= nil and not running then outputText = tostring(value); renderPanel() end
end)
noctalia.state.watch("last_metrics", function(value)
    if value ~= nil then
        metrics = value
        createGauges()
        renderPanel()
    end
end)
noctalia.state.watch("status", function(value)
    if value ~= nil then statusText = tostring(value); renderPanel() end
end)
-- Keep a complete panel tree ready before the first bar click. This avoids a
-- transient empty shell while Noctalia is opening the panel surface.
renderPanel()
