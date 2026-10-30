function update()
    barWidget.setGlyph(noctalia.getConfig("glyph") or "activity")
    if noctalia.getConfig("show_label") == false then
        barWidget.setText("")
    else
        barWidget.setText("SpeedTest")
    end
    barWidget.setTooltip("Abrir o teste de velocidade")
end

function onClick()
    noctalia.togglePanel("vinicius/speedtest:panel")
end
