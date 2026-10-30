--!nonstrict

local watchEnabled = false
local nextRunMs = 0
local serviceBusy = false

local function cleanOutput(text)
    text = tostring(text or "")
    text = string.gsub(text, "\27%[[0-9;?]*[ -/]*[@-~]", "")
    text = string.gsub(text, "\r", "\n")
    text = string.gsub(text, "\n\n\n+", "\n\n")
    return noctalia.string.trim(text)
end

local function watchArgs()
    local args = { "bash", (noctalia.pluginDir() or ".") .. "/speedtest.sh", "--plugin-mode" }
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

local function runWatchTest()
    if serviceBusy or noctalia.state.get("running") == true then return end
    serviceBusy = true
    noctalia.state.set("running", true)
    noctalia.state.set("status", "Watch: executando teste…")
    local accepted = noctalia.runAsync(watchArgs(), function(result)
        serviceBusy = false
        noctalia.state.set("running", false)
        local output = cleanOutput(result.stdout)
        local errorOutput = cleanOutput(result.stderr)
        if errorOutput ~= "" then output = output .. (output ~= "" and "\n\n" or "") .. errorOutput end
        local download, upload, latency, quality = string.match(output, "SPEEDTEST_RESULT|([^|\n]+)|([^|\n]+)|([^|\n]+)|([^|\n]+)")
        if download then
            noctalia.state.set("last_metrics", { download = download, upload = upload, latency = latency, quality = quality })
        end
        local status = result.exitCode == 0 and "Teste automático concluído." or ("Teste automático falhou (código " .. tostring(result.exitCode) .. ").")
        if result.timedOut then status = "O teste automático excedeu o tempo limite." end
        noctalia.state.set("last_output", output)
        noctalia.state.set("status", status)
    end)
    if not accepted then
        serviceBusy = false
        noctalia.state.set("running", false)
        noctalia.state.set("status", "Não foi possível iniciar o teste automático.")
    end
end

noctalia.setUpdateInterval(1000)
noctalia.state.set("watch_label", "Watch desligado")
noctalia.state.watch("watch_enabled", function(value)
    watchEnabled = value == true
    if watchEnabled then
        nextRunMs = noctalia.nowMs()
        noctalia.state.set("watch_label", "Watch ligado · iniciando")
    else
        nextRunMs = 0
        noctalia.state.set("watch_label", "Watch desligado")
    end
end)

function update()
    if not watchEnabled then return end
    local now = noctalia.nowMs()
    if nextRunMs == 0 then nextRunMs = now end
    if now >= nextRunMs and not serviceBusy and noctalia.state.get("running") ~= true then
        local interval = tonumber(noctalia.getConfig("watch_interval")) or 30
        nextRunMs = now + math.max(1, interval) * 60 * 1000
        runWatchTest()
    end
    local remaining = math.max(0, math.ceil((nextRunMs - now) / 1000))
    noctalia.state.set("watch_label", serviceBusy and "Watch ligado · teste em andamento" or ("Watch ligado · próximo em " .. tostring(remaining) .. "s"))
end

function onConfigChanged()
    -- The next interval uses the updated setting.
    if watchEnabled then nextRunMs = noctalia.nowMs() end
end
