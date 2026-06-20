script_name('Translator Ultimate')
script_author('NauTaro')
script_version('7.3')

local ffi, effil, encoding = require('ffi'), require('effil'), require('encoding')
local iconv, imgui, inicfg = require('iconv'), require('mimgui'), require('inicfg')
local u8 = encoding.UTF8
local ok_sampev, sampev = pcall(require, 'samp.events')

local function mkconv(to, from)
    local ok, c = pcall(iconv.new, to .. '//TRANSLIT//IGNORE', from)
    return ok and c or nil
end

local _CONV_CP1251_TO_U8 = mkconv('UTF-8', 'CP1251')
local _CONV_U8_TO_CP1251 = mkconv('CP1251', 'UTF-8')
local _CONV_CP1252_TO_U8 = mkconv('UTF-8', 'CP1252')
local _CONV_U8_TO_CP1252 = mkconv('CP1252', 'UTF-8')

encoding.default = 'CP1252'
local iniFileName = "TranslatorUltimate.ini"
local mainCfg = inicfg.load({config = {my_lang = "ES", server_lang = "PT-BR"}}, iniFileName)
inicfg.save(mainCfg, iniFileName)

local my_lang, server_lang = mainCfg.config.my_lang, mainCfg.config.server_lang
local cache, pending_cached_prints, in_threads = {}, {}, {}
local autotr_enabled, only_clan = false, false
local last_main_tick, flood_protection_until, last_use = os.clock(), 0, 0

local lang_list = {
    {id='ES', name='Español'}, {id='PT-BR', name='Português'},
    {id='EN-US', name='English'}, {id='RU', name='Русский'}, 
    {id='PL', name='Polski'}, {id='ID', name='Bahasa Indonesia'}, 
    {id='AUTO', name='Automático'}
}

local function get_lang_idx(id)
    for i, v in ipairs(lang_list) do if v.id == id then return i - 1 end end
    return 0
end

local function formatLang(l)
    l = l:lower()
    return l == 'en-us' and 'en' or l == 'pt-br' and 'pt' or l == 'id' and 'id' or l == 'pl' and 'pl' or l
end

local menu_active, autotr_cb, only_clan_cb = imgui.new.bool(false), imgui.new.bool(false), imgui.new.bool(false)
local my_lang_idx, srv_lang_idx = imgui.new.int(get_lang_idx(my_lang)), imgui.new.int(get_lang_idx(server_lang))

local ui_L = {
    ['ES'] = {title="Translator mod By NauTaro", my_lang="Mi idioma:", srv_lang="Idioma servidor:", auto_tr="Auto-Translator", only_clan="Solo Clan (!)", langs={"Español", "Português", "Inglés", "Ruso", "Polaco", "Indonesio", "Automático"}, save_btn="Guardar", saved_msg="Configuración guardada."},
    ['PT-BR'] = {title="Translator mod By NauTaro", my_lang="Meu idioma:", srv_lang="Idioma servidor:", auto_tr="Auto-Translator", only_clan="Apenas Clã (!)", langs={"Espanhol", "Português", "Inglês", "Russo", "Polonês", "Indonésio", "Automático"}, save_btn="Salvar", saved_msg="Configuração salva."},
    ['EN-US'] = {title="Translator mod By NauTaro", my_lang="My language:", srv_lang="Server language:", auto_tr="Auto-Translator", only_clan="Clan Only (!)", langs={"Spanish", "Portuguese", "English", "Russian", "Polish", "Indonesian", "Automatic"}, save_btn="Save", saved_msg="Configuration saved."},
    ['RU'] = {title="Translator mod By NauTaro", my_lang="Мой язык:", srv_lang="Язык сервера:", auto_tr="Авто-перевод", only_clan="Только Клан (!)", langs={"Испанский", "Португальский", "Английский", "Русский", "Польский", "Индонезийский", "Автоматически"}, save_btn="Сохранить", saved_msg="Настройки сохранены."},
    ['PL'] = {title="Translator mod By NauTaro", my_lang="Mój język:", srv_lang="Język serwera:", auto_tr="Auto-Tłumacz", only_clan="Tylko Klan (!)", langs={"Hiszpański", "Portugalski", "Angielski", "Rosyjski", "Polski", "Indonezyjski", "Automatyczny"}, save_btn="Zapisz", saved_msg="Zapisano konfigurację."},
    ['ID'] = {title="Translator mod By NauTaro", my_lang="Bahasaku:", srv_lang="Bahasa server:", auto_tr="Auto-Translator", only_clan="Hanya Klan (!)", langs={"Spanyol", "Portugis", "Inggris", "Rusia", "Polandia", "Indonesia", "Otomatis"}, save_btn="Simpan", saved_msg="Konfigurasi disimpan."}
}

local L = {
    ['ES'] = {welcome='{88FF88}Translator mod By NauTaro | {FFFFFF}/trmenu', wait='{FF8800}[TR] Espera...', translating='{FF8800}[TR] Traduciendo...', autotr_on='{88FF88}Auto-TR ON', autotr_off='{FF8888}Auto-TR OFF', clan_on='{88FF88}Solo Clan ON', clan_off='{FF8888}Solo Clan OFF'},
    ['PT-BR'] = {welcome='{88FF88}Translator mod By NauTaro | {FFFFFF}/trmenu', wait='{FF8800}[TR] Espere...', translating='{FF8800}[TR] Traduzindo...', autotr_on='{88FF88}Auto-TR ON', autotr_off='{FF8888}Auto-TR OFF', clan_on='{88FF88}Apenas Clã ON', clan_off='{FF8888}Apenas Clã OFF'},
    ['EN-US'] = {welcome='{88FF88}Translator mod By NauTaro | {FFFFFF}/trmenu', wait='{FF8800}[TR] Wait...', translating='{FF8800}[TR] Translating...', autotr_on='{88FF88}Auto-TR ON', autotr_off='{FF8888}Auto-TR OFF', clan_on='{88FF88}Clan Only ON', clan_off='{FF8888}Clan Only OFF'},
    ['RU'] = {welcome='{88FF88}Translator mod By NauTaro | {FFFFFF}/trmenu', wait='{FF8800}[TR] Подождите...', translating='{FF8800}[TR] Перевод...', autotr_on='{88FF88}Авто-ТР ВКЛ', autotr_off='{FF8888}Авто-ТР ВЫКЛ', clan_on='{88FF88}Только Клан ВКЛ', clan_off='{FF8888}Только Клан ВЫКЛ'},
    ['PL'] = {welcome='{88FF88}Translator mod By NauTaro | {FFFFFF}/trmenu', wait='{FF8800}[TR] Czekaj...', translating='{FF8800}[TR] Tlumaczenie...', autotr_on='{88FF88}Auto-TR WL', autotr_off='{FF8888}Auto-TR WYL', clan_on='{88FF88}Tylko Klan WL', clan_off='{88FF88}Tylko Klan WYL'},
    ['ID'] = {welcome='{88FF88}Translator mod By NauTaro | {FFFFFF}/trmenu', wait='{FF8800}[TR] Tunggu...', translating='{FF8800}[TR] Menerjemahkan...', autotr_on='{88FF88}Auto-TR NYALA', autotr_off='{FF8888}Auto-TR MATI', clan_on='{88FF88}Hanya Klan NYALA', clan_off='{88FF88}Hanya Klan MATI'}
}

local function isRU(lang) return lang == 'RU' or lang == 'ru' end

function chat(txt)
    if (txt:find('\xD0[\x80-\xBF]') or txt:find('\xD1[\x80-\x8F]')) and _CONV_U8_TO_CP1251 then
        local r = _CONV_U8_TO_CP1251:iconv(txt)
        if r and r ~= '' then txt = r end
    elseif (txt:find('\xC3[\x80-\xBF]') or txt:find('\xC2[\x80-\xBF]')) and _CONV_U8_TO_CP1252 then
        local r = _CONV_U8_TO_CP1252:iconv(txt)
        if r and r ~= '' then txt = r end
    end
    sampAddChatMessage(txt, -1)
end

imgui.OnInitialize(function()
    local config = imgui.ImFontConfig()
    config.MergeMode = true
    imgui.GetIO().Fonts:AddFontFromFileTTF(getFolderPath(0x14) .. '\\arial.ttf', 14.0, nil, imgui.GetIO().Fonts:GetGlyphRangesCyrillic())
    local style = imgui.GetStyle()
    local colors = style.Colors
    style.WindowRounding, style.FrameRounding = 6.0, 4.0
    style.WindowTitleAlign = imgui.ImVec2(0.5, 0.5)
    colors[imgui.Col.WindowBg] = imgui.ImVec4(0.10, 0.10, 0.12, 0.95)
    colors[imgui.Col.TitleBg] = imgui.ImVec4(0.12, 0.12, 0.14, 1.00)
    colors[imgui.Col.TitleBgActive] = imgui.ImVec4(0.15, 0.40, 0.70, 1.00)
    colors[imgui.Col.Button] = imgui.ImVec4(0.15, 0.40, 0.70, 1.00)
    colors[imgui.Col.ButtonHovered] = imgui.ImVec4(0.20, 0.45, 0.75, 1.00)
    colors[imgui.Col.ButtonActive] = imgui.ImVec4(0.10, 0.35, 0.60, 1.00)
end)

imgui.OnFrame(function() return menu_active[0] end, function()
    local resX, resY = getScreenResolution()
    imgui.SetNextWindowPos(imgui.ImVec2(resX / 2, resY / 2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
    imgui.SetNextWindowSize(imgui.ImVec2(340, 240), imgui.Cond.FirstUseEver)
    local texts = ui_L[my_lang] or ui_L['ES']

    imgui.Begin(texts.title, menu_active, imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoResize)
    imgui.Spacing() imgui.Text(texts.my_lang) imgui.PushItemWidth(-1)
    if imgui.BeginCombo("##mylang", texts.langs[my_lang_idx[0] + 1]) then
        for i = 1, #lang_list - 1 do
            if imgui.Selectable(texts.langs[i], my_lang_idx[0] == i - 1) then my_lang_idx[0] = i - 1; my_lang = lang_list[i].id end
        end
        imgui.EndCombo()
    end
    imgui.PopItemWidth() imgui.Spacing() imgui.Text(texts.srv_lang) imgui.PushItemWidth(-1)
    if imgui.BeginCombo("##srvlang", texts.langs[srv_lang_idx[0] + 1]) then
        for i, name in ipairs(texts.langs) do
            if imgui.Selectable(name, srv_lang_idx[0] == i - 1) then srv_lang_idx[0] = i - 1; server_lang = lang_list[i].id end
        end
        imgui.EndCombo()
    end
    imgui.PopItemWidth() imgui.Spacing() imgui.Separator() imgui.Spacing()

    autotr_cb[0] = autotr_enabled
    if imgui.Checkbox(texts.auto_tr, autotr_cb) then 
        autotr_enabled = autotr_cb[0] 
        chat(autotr_enabled and L[my_lang].autotr_on or L[my_lang].autotr_off)
    end
    imgui.SameLine()
    only_clan_cb[0] = only_clan
    if imgui.Checkbox(texts.only_clan, only_clan_cb) then 
        only_clan = only_clan_cb[0] 
        chat(only_clan and L[my_lang].clan_on or L[my_lang].clan_off)
    end
    imgui.Spacing()

    if imgui.Button(texts.save_btn, imgui.ImVec2(-1, 30)) then
        mainCfg.config.my_lang, mainCfg.config.server_lang = lang_list[my_lang_idx[0] + 1].id, lang_list[srv_lang_idx[0] + 1].id
        if inicfg.save(mainCfg, iniFileName) then
            my_lang, server_lang = mainCfg.config.my_lang, mainCfg.config.server_lang
            chat("{88FF88}[Translator] {FFFFFF}" .. texts.saved_msg)
        end
    end
    imgui.End()
end)

local function to_utf8(str, lang)
    local is_ru = isRU(lang)
    local conv = is_ru and _CONV_CP1251_TO_U8 or _CONV_CP1252_TO_U8
    if conv then
        local res = conv:iconv(str)
        if res and res ~= '' then return res end
    end
    local saved = encoding.default
    encoding.default = is_ru and 'CP1251' or 'CP1252'
    local ok, res = pcall(function() return u8(str) end)
    encoding.default = saved
    return (ok and res and res ~= '') and res or str
end

local function from_utf8(str, lang)
    local is_ru = isRU(lang)
    local conv = is_ru and _CONV_U8_TO_CP1251 or _CONV_U8_TO_CP1252
    if conv then
        local res = conv:iconv(str)
        if res and res ~= '' then return res end
    end
    local saved = encoding.default
    encoding.default = is_ru and 'CP1251' or 'CP1252'
    local ok, res = pcall(function() return u8:decode(str) end)
    encoding.default = saved
    return (ok and res and res ~= '') and res or str
end

local slang_dict = {
    ['PT-BR'] = {["mlk"]="moleque", ["mds"]="meu deus", ["xitado"]="usando hack", ["xiter"]="hacker", ["pdp"]="com certeza", ["vlw"]="obrigado", ["flw"]="adeus", ["blz"]="beleza", ["tlgd"]="entendeu", ["fdp"]="filho da puta", ["slc"]="voce e louco", ["nmrl"]="falando serio", ["tmj"]="conta comigo", ["vdd"]="verdade", ["pq"]="por que", ["vc"]="voce", ["tbm"]="tambem", ["krl"]="caralho", ["pqp"]="puta que pariu", ["rlx"]="relaxa", ["sv"]="servidor", ["nd"]="nada", ["pfv"]="por favor", ["mto"]="muito", ["tmnc"]="tomar no cu", ["poha"]="porra", ["nb"]="novato", ["dms"]="demais", ["ain"]="ay", ["ss"]="sim", ["nn"]="nao", ["s"]="sim", ["n"]="nao", ["mano"]="hermano"},
    ['ES'] = {["q"]="que", ["xq"]="por que", ["pq"]="por que", ["tmb"]="tambien", ["xfa"]="por favor", ["grax"]="gracias", ["hdp"]="hijo de puta", ["ctm"]="concha tu madre", ["wbn"]="huevon", ["k"]="que", ["ptm"]="puta madre", ["np"]="no hay problema", ["klq"]="que pasa", ["weon"]="amigo", ["wn"]="amigo", ["s"]="si", ["n"]="no"},
    ['EN-US'] = {["u"]="you", ["r"]="are", ["pls"]="please", ["plz"]="please", ["thx"]="thanks", ["ty"]="thank you", ["idk"]="i dont know", ["afk"]="away from keyboard", ["omg"]="oh my god", ["wtf"]="what the fuck", ["lmao"]="laughing my ass off", ["lol"]="laughing out loud", ["np"]="no problem", ["brb"]="be right back", ["gg"]="good game", ["btw"]="by the way"},
    ['RU'] = {["спс"]="спасибо", ["пж"]="пожалуйста", ["хз"]="не знаю", ["мг"]="метагейминг", ["дб"]="драйвбай", ["дм"]="дэтматч", ["пздц"]="пиздец", ["блять"]="блин", ["ок"]="хорошо"},
    ['PL'] = {["zw"]="zaraz wracam", ["jj"]="juz jestem", ["thx"]="dzieki", ["nmzc"]="nie ma za co"},
    ['ID'] = {["yg"]="yang", ["dgn"]="dengan", ["klo"]="kalau", ["gw"]="saya", ["lu"]="kamu"}
}

if _CONV_U8_TO_CP1251 then
    local new_ru = {}
    for k, v in pairs(slang_dict['RU']) do
        local ck, cv = _CONV_U8_TO_CP1251:iconv(k), _CONV_U8_TO_CP1251:iconv(v)
        if ck and ck ~= '' and cv and cv ~= '' then new_ru[ck] = cv end
    end
    slang_dict['RU'] = new_ru
end

local function processSlang(str, lang)
    return str:gsub("(%a)%1%1%1+", "%1%1"):gsub("%a+", function(word)
        local w = word:lower()
        if lang ~= 'AUTO' and slang_dict[lang] and slang_dict[lang][w] then
            return word == word:upper() and slang_dict[lang][w]:upper() or slang_dict[lang][w]
        elseif lang == 'AUTO' then
            for _, dict in pairs(slang_dict) do
                if dict[w] then return word == word:upper() and dict[w]:upper() or dict[w] end
            end
        end
        return word
    end)
end

local function isGibberish(text)
    if not text or text:match("^%s*$") then return true end
    local _, cmds = text:gsub("/%w+", "")
    if cmds > 2 then return true end
    local pure = text:gsub("[%s%p]", ""):lower()
    return pure:match("^k+$") or pure:match("^x+d+$") or pure:match("^j+a+$")
end

local worker = effil.thread(function(utf8_text, source_lang, target_lang)
    local ffi = require 'ffi'
    pcall(ffi.cdef, [[
        typedef void* HINTERNET; typedef unsigned long DWORD; typedef int BOOL;
        HINTERNET InternetOpenA(const char* a, DWORD b, const char* c, const char* d, DWORD e);
        HINTERNET InternetOpenUrlA(HINTERNET h, const char* url, const char* hdr, DWORD hl, DWORD flags, DWORD* ctx);
        BOOL InternetReadFile(HINTERNET f, void* buf, DWORD n, DWORD* read);
        BOOL InternetCloseHandle(HINTERNET h);
    ]])
    local wi = ffi.load('wininet')
    local ue = utf8_text:gsub('([^%w%-%.%_%~ ])', function(c) return string.format('%%%02X', string.byte(c)) end):gsub(' ', '+')
    local url = 'https://translate.googleapis.com/translate_a/single?client=gtx&sl=' .. source_lang .. '&tl=' .. target_lang .. '&dt=t&q=' .. ue
    local req_headers = "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64)\r\nConnection: close\r\n"
    local ctx = ffi.new('DWORD[1]', 0)
    local hNet = wi.InternetOpenA('Mozilla/5.0', 0, nil, nil, 0)
    if not hNet then return false, '' end
    local hUrl = wi.InternetOpenUrlA(hNet, url, req_headers, #req_headers, 0x84000000, ctx)
    if not hUrl then wi.InternetCloseHandle(hNet); return false, '' end

    local chunks, totalRead, buf, nRead = {}, 0, ffi.new('char[8192]'), ffi.new('DWORD[1]')
    while totalRead < 32768 do
        if wi.InternetReadFile(hUrl, buf, 8192, nRead) == 0 or nRead[0] == 0 then break end
        chunks[#chunks + 1] = ffi.string(buf, nRead[0])
        totalRead = totalRead + nRead[0]
    end
    wi.InternetCloseHandle(hUrl)
    wi.InternetCloseHandle(hNet)
    return true, table.concat(chunks)
end)

local pending_out = nil

local function doTranslate(text)
    text = text:gsub('^%s*["\'](.+)["\']%s*$', '%1'):gsub('^%s+', ''):gsub('%s+$', '')
    local p = text:match("^([!@#$*]+)")
    local prefix = p or ""
    if p then text = text:sub(#p + 1):gsub('^%s+', '') end

    if only_clan and not prefix:find('!') then
        prefix = "!" .. prefix
    end

    if text == '' then return end

    local utf8_msg = to_utf8(text, my_lang)
    local cache_key = server_lang .. "|" .. utf8_msg

    if cache[cache_key] then return sampSendChat(prefix .. cache[cache_key]) end
    if pending_out then return chat(L[my_lang].wait) end

    local now = os.clock()
    if (now - last_use) < 1.0 then return end
    last_use = now

    chat(L[my_lang].translating)
    local tl_fmt = server_lang == 'AUTO' and 'en' or formatLang(server_lang)
    pending_out = {thread = worker(utf8_msg, formatLang(my_lang), tl_fmt), original = text, prefix = prefix, key = cache_key, target_lang = server_lang}
end

if ok_sampev then
    function sampev.onServerMessage(color, text)
        local clean_text = text:gsub("{%x%x%x%x%x%x}", "")
        
        if clean_text:find('/ZVH') then return end

        local current_time = os.clock()
        if (current_time - last_main_tick > 0.5) or isGamePaused() then
            flood_protection_until = current_time + 1.5
            in_threads = {}
        end

        if current_time < flood_protection_until or not autotr_enabled then return end

        if (only_clan and not clean_text:find('%(!%)')) or clean_text:find('%[TR%]') or clean_text:find('%[Auto%-TR%]') then return end

        if clean_text:find("%(%d+%)%s*:") or clean_text:find(":%s*") then
            local prefix, actual_msg = clean_text:match("^(.-%:%s*)(.+)$")
            if not actual_msg then prefix, actual_msg = "", clean_text end
            if isGibberish(actual_msg) then return end

            local detect_encoding = actual_msg:find('[\192-\255\168\184]') and 'RU' or 'AUTO'
            local processed_msg = processSlang(actual_msg, server_lang)
            if processed_msg == "" or processed_msg:match("^%s*$") then return end

            local utf8_msg = to_utf8(processed_msg, detect_encoding)
            local cache_key = my_lang .. "|" .. utf8_msg

            if cache[cache_key] then
                table.insert(pending_cached_prints, '{88FF88}[Auto-TR] ' .. prefix .. cache[cache_key])
                return
            end

            table.insert(in_threads, {thread = worker(utf8_msg, 'auto', formatLang(my_lang)), prefix = prefix, original_msg = processed_msg, key = cache_key, target_lang = my_lang})
        end
    end
end

sampRegisterChatCommand('tr', doTranslate)
sampRegisterChatCommand('autotr', function()
    autotr_enabled = not autotr_enabled
    chat(autotr_enabled and L[my_lang].autotr_on or L[my_lang].autotr_off)
end)
sampRegisterChatCommand('trmenu', function() menu_active[0] = not menu_active[0] end)

function main()
    while not isSampAvailable() do wait(100) end
    chat(L[my_lang].welcome)
    last_main_tick = os.clock()

    while true do
        wait(0)
        last_main_tick = os.clock()

        if menu_active[0] and (isGamePaused() or wasKeyPressed(0x1B)) then
            menu_active[0] = false
        end

        if #pending_cached_prints > 0 then
            for _, msg in ipairs(pending_cached_prints) do chat(msg) end
            pending_cached_prints = {}
        end

        if pending_out then
            local status = pending_out.thread:status()
            if status == 'completed' then
                local ok, raw_body = pending_out.thread:get()
                if ok and raw_body and raw_body ~= '' then
                    local p_ok, parsed = pcall(decodeJson, raw_body)
                    if p_ok and type(parsed) == 'table' and type(parsed[1]) == 'table' then
                        local full_translation = ""
                        for _, block in ipairs(parsed[1]) do
                            if type(block) == 'table' and type(block[1]) == 'string' then full_translation = full_translation .. block[1] end
                        end
                        if full_translation ~= "" then
                            local result = from_utf8(full_translation:gsub("\n", " "), pending_out.target_lang)
                            cache[pending_out.key] = result
                            sampSendChat(pending_out.prefix .. result)
                        end
                    end
                end
                pending_out = nil
            elseif status == 'failed' then pending_out = nil end
        end

        for i = #in_threads, 1, -1 do
            local item, status = in_threads[i], in_threads[i].thread:status()
            if status == 'completed' then
                local ok, raw_body = item.thread:get()
                if ok and raw_body and raw_body ~= '' then
                    local p_ok, parsed = pcall(decodeJson, raw_body)
                    if p_ok and type(parsed) == 'table' and type(parsed[1]) == 'table' then
                        local full_translation = ""
                        for _, block in ipairs(parsed[1]) do
                            if type(block) == 'table' and type(block[1]) == 'string' then full_translation = full_translation .. block[1] end
                        end
                        if full_translation ~= "" then
                            local result = from_utf8(full_translation:gsub("\n", " "), item.target_lang)
                            local clean_original = item.original_msg:lower():gsub("[%p%s]", "")
                            local clean_result = result:lower():gsub("[%p%s]", "")
                            if clean_result ~= clean_original and #clean_result > 0 then
                                cache[item.key] = result
                                chat('{88FF88}[Auto-TR] ' .. item.prefix .. result)
                            end
                        end
                    end
                end
                table.remove(in_threads, i)
            elseif status == 'failed' then table.remove(in_threads, i) end
        end
    end
end