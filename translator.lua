do
	script_name("Translator mod");
	script_author("NauTaro");
	script_version("1.4");
	local SCRIPT_VERSION = "1.4";
	local ffi, effil, encoding = require("ffi"), require("effil"), require("encoding");
	local iconv, imgui, inicfg = require("iconv"), require("mimgui"), require("inicfg");
	local memory = require("memory");
	local u8 = encoding.UTF8;
	local ok_sampev, sampev = pcall(require, "samp.events");
	local ok_updater, updater = pcall(require, "translator_updater");
	local function mkconv(to, from)
		local ok, c = pcall(iconv.new, to .. "//TRANSLIT//IGNORE", from);
		return (ok and c) or nil;
	end
	local _CONV_CP1251_TO_U8 = mkconv("UTF-8", "CP1251");
	local _CONV_U8_TO_CP1251 = mkconv("CP1251", "UTF-8");
	local _CONV_CP1252_TO_U8 = mkconv("UTF-8", "CP1252");
	local _CONV_U8_TO_CP1252 = mkconv("CP1252", "UTF-8");
	local _CONV_CP1250_TO_U8 = mkconv("UTF-8", "CP1250");
	local _CONV_U8_TO_CP1250 = mkconv("CP1250", "UTF-8");
	encoding.default = "CP1252";
	local iniFileName = "TranslatorUltimate.ini";
	local mainCfg = inicfg.load({config={my_lang="ES",server_lang="PT-BR",out_lang="EN-US",menu_tr=true,chat_translation_mode="automatic",auto_translate_out=true,auto_update=true,auto_update_url="https://raw.githubusercontent.com/NauTaro/translator-ultimate/main/version.json",hotkey_menu=118,hotkey_auto=119},theme={auto_color=true,custom_r=0.15,custom_g=0.4,custom_b=0.7},servers={}}, iniFileName);
	if (type(mainCfg.servers) ~= "table") then
		mainCfg.servers = {};
	end
	do
		local clean_servers = {};
		for k, v in pairs(mainCfg.servers) do
			if (type(v) == "string") then
				clean_servers[k] = v;
			end
		end
		mainCfg.servers = clean_servers;
	end
	inicfg.save(mainCfg, iniFileName);
	local my_lang, server_lang, out_lang = mainCfg.config.my_lang, mainCfg.config.server_lang, mainCfg.config.out_lang;
	local cache = {};
	local cache_order = {};
	local function mem_cache_put(key, value)
		if (cache[key] == nil) then
			table.insert(cache_order, key);
			if (#cache_order > 500) then
				cache[table.remove(cache_order, 1)] = nil;
			end
		end
		cache[key] = value;
	end
	local function cfg_switch(value, fallback)
		if (value == nil) then
			return fallback;
		end
		return not ((value == false) or (value == "false") or (value == 0) or (value == "0"));
	end
	local legacy_menu_enabled = cfg_switch(mainCfg.config.menu_tr, true);
	local chat_tr_enabled = cfg_switch(mainCfg.config.translate_chat, true);
	local chat_translation_mode = ((mainCfg.config.chat_translation_mode == "messages") and "messages") or "automatic";
	local menu_tr_enabled = cfg_switch(mainCfg.config.translate_menus, legacy_menu_enabled);
	local head_tr_enabled = cfg_switch(mainCfg.config.translate_above_head, true);
	local text3d_tr_enabled = cfg_switch(mainCfg.config.translate_3d, true);
	local autotr_enabled, only_clan, auto_out_enabled = chat_tr_enabled, false, cfg_switch(mainCfg.config.auto_translate_out, true);
	local auto_update_enabled = cfg_switch(mainCfg.config.auto_update, true);
	local auto_update_url = tostring(mainCfg.config.auto_update_url or "");
	local upd_check_thread, upd_check_started, upd_dl_thread, upd_dl_started, upd_new_version = nil, 0, nil, 0, nil;
	local hotkey_menu_vk = tonumber(mainCfg.config.hotkey_menu) or 118;
	local hotkey_auto_vk = tonumber(mainCfg.config.hotkey_auto) or 119;
	local last_main_tick, flood_protection_until, last_use = os.clock(), 0, 0;
	local lang_list = {{id="ES",name="Español"},{id="PT-BR",name="Português"},{id="EN-US",name="English"},{id="RU",name="Русский"},{id="PL",name="Polski"},{id="ID",name="Bahasa Indonesia"},{id="TR",name="Türkçe"},{id="CS",name="Čeština"},{id="RO",name="Romana"},{id="AUTO",name="Automático"}};
	local function get_lang_idx(id)
		for i, v in ipairs(lang_list) do
			if (v.id == id) then
				return i - 1;
			end
		end
		return 0;
	end
	local function formatLang(l)
		l = l:lower();
		return ((l == "en-us") and "en") or ((l == "pt-br") and "pt") or ((l == "id") and "id") or ((l == "pl") and "pl") or ((l == "cs") and "cs") or ((l == "czech") and "cs") or l;
	end
	local menu_active = imgui.new.bool(false);
	local chat_auto_cb = imgui.new.bool(chat_tr_enabled and (chat_translation_mode == "automatic"));
	local chat_messages_cb = imgui.new.bool(chat_tr_enabled and (chat_translation_mode == "messages"));
	local menu_tr_cb = imgui.new.bool(menu_tr_enabled);
	local head_tr_cb = imgui.new.bool(head_tr_enabled);
	local text3d_tr_cb = imgui.new.bool(text3d_tr_enabled);
	local only_clan_cb = imgui.new.bool(false);
	local auto_out_cb = imgui.new.bool(auto_out_enabled);
	local auto_update_cb = imgui.new.bool(auto_update_enabled);
	local config_dirty = false;
	local menu_tr_lbl = {ES="Traducir menus",["PT-BR"]="Traduzir menus",["EN-US"]="Translate menus",RU="Перевод меню",PL="Tlumacz menu",ID="Terjemahkan menu",TR="Menuleri cevir",CS="Prekladat menu",RO="Traducere meniuri"};
	local current_tab = imgui.new.int(1);
	local my_lang_idx = imgui.new.int(get_lang_idx(my_lang));
	local srv_lang_idx = imgui.new.int(get_lang_idx(server_lang));
	local out_lang_idx = imgui.new.int(get_lang_idx(out_lang));
	local ui_L = {ES={title="Translator mod By NauTaro",tab1="Configuración",tab2="Colores",tab3="Créditos",my_lang="Mi idioma:",srv_lang="Idioma servidor (Lectura):",out_lang="Idioma a transmitir (/tr):",auto_tr="Auto-Translator",only_clan="Solo Clan (!)",auto_col="Color automático (HUD)",man_col="Color manual",langs={"Español","Português","Inglés","Ruso","Polaco","Indonesio","Turco","Checo","Rumano","Automático"},save_btn="Guardar Cambios",saved_msg="Configuración guardada.",author="Creado por NauTaro",discord="Discord: @nautaro"},["PT-BR"]={title="Translator mod By NauTaro",tab1="Configuração",tab2="Cores",tab3="Créditos",my_lang="Meu idioma:",srv_lang="Idioma servidor (Leitura):",out_lang="Idioma de transmissão (/tr):",auto_tr="Auto-Translator",only_clan="Apenas Clã (!)",auto_col="Cor automática (HUD)",man_col="Cor manual",langs={"Espanhol","Português","Inglês","Russo","Polonês","Indonésio","Turco","Tcheco","Romeno","Automático"},save_btn="Salvar",saved_msg="Configuração salva.",author="Criado por NauTaro",discord="Discord: @nautaro"},["EN-US"]={title="Translator mod By NauTaro",tab1="Configuration",tab2="Colors",tab3="Credits",my_lang="My language:",srv_lang="Server lang (Reading):",out_lang="Transmit lang (/tr):",auto_tr="Auto-Translator",only_clan="Clan Only (!)",auto_col="Auto color (HUD)",man_col="Manual color",langs={"Spanish","Portuguese","English","Russian","Polish","Indonesian","Turkish","Czech","Romanian","Automatic"},save_btn="Save",saved_msg="Configuration saved.",author="Created by NauTaro",discord="Discord: @nautaro"},RU={title="Translator mod By NauTaro",tab1="Настройки",tab2="Цвета",tab3="Авторы",my_lang="Мой язык:",srv_lang="Язык сервера (Чтение):",out_lang="Язык передачи (/tr):",auto_tr="Авто-перевод",only_clan="Только Клан (!)",auto_col="Авто-цвет (HUD)",man_col="Ручной цвет",langs={"Испанский","Португальский","Английский","Русский","Польский","Индонезийский","Турецкий","Чешский","Румынский","Автоматически"},save_btn="Сохранить",saved_msg="Настройки сохранены.",author="Создатель: NauTaro",discord="Discord: @nautaro"},PL={title="Translator mod By NauTaro",tab1="Konfiguracja",tab2="Kolory",tab3="Twórcy",my_lang="Mój język:",srv_lang="Język serwera (Odczyt):",out_lang="Język transmisji (/tr):",auto_tr="Auto-Tłumacz",only_clan="Tylko Klan (!)",auto_col="Auto-Kolor (HUD)",man_col="Ręczny kolor",langs={"Hiszpański","Portugalski","Angielski","Rosyjski","Polski","Indonezyjski","Turecki","Czeski","Rumuński","Automatyczny"},save_btn="Zapisz",saved_msg="Zapisano konfigurację.",author="Stworzone przez NauTaro",discord="Discord: @nautaro"},ID={title="Translator mod By NauTaro",tab1="Konfigurasi",tab2="Warna",tab3="Kredit",my_lang="Bahasaku:",srv_lang="Bahasa server (Membaca):",out_lang="Bahasa transmisi (/tr):",auto_tr="Auto-Translator",only_clan="Hanya Klan (!)",auto_col="Warna otomatis (HUD)",man_col="Warna manual",langs={"Spanyol","Portugis","Inggris","Rusia","Polandia","Indonesia","Turki","Ceko","Rumania","Otomatis"},save_btn="Simpan",saved_msg="Konfigurasi disimpan.",author="Dibuat oleh NauTaro",discord="Discord: @nautaro"},TR={title="Translator mod By NauTaro",tab1="Yapılandırma",tab2="Renkler",tab3="Krediler",my_lang="Dilim:",srv_lang="Sunucu dili (Okuma):",out_lang="Iletim dili (/tr):",auto_tr="Oto-Çevirmen",only_clan="Sadece Klan (!)",auto_col="Otomatik renk (HUD)",man_col="Manuel renk",langs={"İspanyolca","Portekizce","İngilizce","Rusça","Lehçe","Endonezce","Türkçe","Çekçe","Romence","Otomatik"},save_btn="Kaydet",saved_msg="Yapılandırma kaydedildi.",author="NauTaro tarafından",discord="Discord: @nautaro"},CS={title="Translator mod By NauTaro",tab1="Nastavení",tab2="Barvy",tab3="Kredity",my_lang="Můj jazyk:",srv_lang="Jazyk serveru (Čtení):",out_lang="Jazyk vysílání (/tr):",auto_tr="Auto-Překladač",only_clan="Pouze klan (!)",auto_col="Automatická barva (HUD)",man_col="Manuální barva",langs={"Španělština","Portugalština","Angličtina","Ruština","Polština","Indonéština","Turečtina","Čeština","Rumunština","Automatický"},save_btn="Uložit",saved_msg="Nastavení uloženo.",author="Vytvořil NauTaro",discord="Discord: @nautaro"},RO={title="Translator mod By NauTaro",tab1="Configurare",tab2="Culori",tab3="Credite",my_lang="Limba mea:",srv_lang="Limba serverului (Citire):",out_lang="Limba de transmisie (/tr):",auto_tr="Auto-Traducator",only_clan="Doar Clan (!)",auto_col="Culoare automata (HUD)",man_col="Culoare manuala",langs={"Spaniola","Portugheza","Engleza","Rusa","Poloneza","Indoneziana","Turca","Ceha","Romana","Automat"},save_btn="Salveaza",saved_msg="Configuratie salvata.",author="Creat de NauTaro",discord="Discord: @nautaro"}};
	local L = {ES={welcome="{27F595}Translator mod By NauTaro | {FFFFFF}/trmenu",wait="{27F595}[TR] Espera...",translating="{27F595}[TR] Traduciendo...",autotr_on="{27F595}Auto-TR ON",autotr_off="{FF8888}Auto-TR OFF",clan_on="{27F595}Solo Clan ON",clan_off="{FF8888}Solo Clan OFF"},["PT-BR"]={welcome="{27F595}Translator mod By NauTaro | {FFFFFF}/trmenu",wait="{27F595}[TR] Espere...",translating="{27F595}[TR] Traduzindo...",autotr_on="{27F595}Auto-TR ON",autotr_off="{FF8888}Auto-TR OFF",clan_on="{27F595}Apenas Clã ON",clan_off="{FF8888}Apenas Clã OFF"},["EN-US"]={welcome="{27F595}Translator mod By NauTaro | {FFFFFF}/trmenu",wait="{27F595}[TR] Wait...",translating="{27F595}[TR] Translating...",autotr_on="{27F595}Auto-TR ON",autotr_off="{FF8888}Auto-TR OFF",clan_on="{27F595}Clan Only ON",clan_off="{FF8888}Clan Only OFF"},RU={welcome="{27F595}Translator mod By NauTaro | {FFFFFF}/trmenu",wait="{27F595}[TR] Подождите...",translating="{27F595}[TR] Перевод...",autotr_on="{27F595}Авто-ТР ВКЛ",autotr_off="{FF8888}Авто-ТР ВЫКЛ",clan_on="{27F595}Только Клан ВКЛ",clan_off="{FF8888}Только Клан ВЫКЛ"},PL={welcome="{27F595}Translator mod By NauTaro | {FFFFFF}/trmenu",wait="{27F595}[TR] Czekaj...",translating="{27F595}[TR] Tlumaczenie...",autotr_on="{27F595}Auto-TR WL",autotr_off="{FF8888}Auto-TR WYL",clan_on="{27F595}Tylko Klan WL",clan_off="{FF8888}Tylko Klan WYL"},ID={welcome="{27F595}Translator mod By NauTaro | {FFFFFF}/trmenu",wait="{27F595}[TR] Tunggu...",translating="{27F595}[TR] Menerjemahkan...",autotr_on="{27F595}Auto-TR NYALA",autotr_off="{FF8888}Auto-TR MATI",clan_on="{27F595}Hanya Klan NYALA",clan_off="{FF8888}Hanya Klan MATI"},TR={welcome="{27F595}Translator mod By NauTaro | {FFFFFF}/trmenu",wait="{27F595}[TR] Bekle...",translating="{27F595}[TR] Çevriliyor...",autotr_on="{27F595}Oto-TR AÇIK",autotr_off="{FF8888}Oto-TR KAPALI",clan_on="{27F595}Sadece Klan AÇIK",clan_off="{FF8888}Sadece Klan KAPALI"},CS={welcome="{27F595}Translator mod By NauTaro | {FFFFFF}/trmenu",wait="{27F595}[TR] Čekejte...",translating="{27F595}[TR] Překládám...",autotr_on="{27F595}Auto-TR ZAP",autotr_off="{FF8888}Auto-TR VYP",clan_on="{27F595}Pouze klan ZAP",clan_off="{FF8888}Pouze klan VYP"},RO={welcome="{27F595}Translator mod By NauTaro | {FFFFFF}/trmenu",wait="{27F595}[TR] Asteapta...",translating="{27F595}[TR] Se traduce...",autotr_on="{27F595}Auto-TR PORNIT",autotr_off="{FF8888}Auto-TR OPRIT",clan_on="{27F595}Doar Clan PORNIT",clan_off="{FF8888}Doar Clan OPRIT"}};
	local function isRU(lang)
		return (lang == "RU") or (lang == "ru");
	end
	local function isCE(lang)
		return (lang == "RO") or (lang == "PL") or (lang == "CS") or (lang == "ro") or (lang == "pl") or (lang == "cs");
	end
	local function normalize_ro(str)
		if not str then
			return str;
		end
		str = str:gsub("\xC8\x99", "\xC5\x9F");
		str = str:gsub("\xC8\x98", "\xC5\x9E");
		str = str:gsub("\xC8\x9B", "\xC5\xA3");
		str = str:gsub("\xC8\x9A", "\xC5\xA2");
		return str;
	end
	local RO_FOLD = {["\xC4\x83"]="a",["\xC4\x82"]="A",["\xC3\xA2"]="a",["\xC3\x82"]="A",["\xC3\xAE"]="i",["\xC3\x8E"]="I",["\xC8\x99"]="s",["\xC8\x98"]="S",["\xC5\x9F"]="s",["\xC5\x9E"]="S",["\xC8\x9B"]="t",["\xC8\x9A"]="T",["\xC5\xA3"]="t",["\xC5\xA2"]="T"};
	local function ro_fold_ascii(s)
		return (s:gsub("[\xC3\xC4\xC5\xC8][\x80-\xBF]", RO_FOLD));
	end
	local function looks_cyrillic(str)
		if not str then
			return false;
		end
		local hi, letters = 0, 0;
		for i = 1, #str do
			local b = str:byte(i);
			if (((b >= 192) and (b <= 255)) or (b == 168) or (b == 184)) then
				hi = hi + 1;
				letters = letters + 1;
			elseif (((b >= 65) and (b <= 90)) or ((b >= 97) and (b <= 122))) then
				letters = letters + 1;
			end
		end
		return (letters >= 2) and ((hi / letters) > 0.4);
	end
	local PROTECT_TERMS = {freeroam=true,deathmatch=true,derby=true,score=true,fps=true,ping=true,spree=true,spawn=true,respawn=true,gps=true,hud=true,dm=true,tdm=true,ctf=true,vip=true,admin=true,noob=true,lag=true,kit=true,skin=true,hp=true,ammo=true,kill=true,kills=true,headshot=true,nick=true,ban=true,kick=true,mute=true,afk=true};
	local PROTECT_PHRASES = {"Desert Eagle","Paint Ball","Los Santos","San Fierro","Las Venturas","Los Santos News","LS News","SF News","LV News","SA:MP","SAMP","LS/SF/LV","GPS","HUD","Health","Armor","Score","Ping","Money","Level","Freeroam","Cops and Robbers","COPS AND ROBBERS","X1W","X1","Walk","WALK","Arena","ARENA"};
	PROTECT_TERMS.arena = true;
	PROTECT_TERMS.x1w = true;
	PROTECT_TERMS.walk = true;
	PROTECT_TERMS.mood = true;
	PROTECT_TERMS.ls = true;
	PROTECT_TERMS.lv = true;
	PROTECT_TERMS.sf = true;
	local function escape_lua_pattern(value)
		return (value:gsub("([^%w])", "%%%1"));
	end
	local function mask_protect(text)
		local map, n = {}, 0;
		local function put(tok)
			n = n + 1;
			map[n] = tok;
			return "{{" .. n .. "}}";
		end
		local out = text;
		for _, phrase in ipairs(PROTECT_PHRASES) do
			out = out:gsub(escape_lua_pattern(phrase), put);
		end
		out = out:gsub("{%x%x%x%x%x%x}", put);
		out = out:gsub("~[%a%d]~", put);
		out = out:gsub("%b[]", put);
		out = out:gsub("/[%w_]+", put);
		out = out:gsub("%a+", function(w)
			if PROTECT_TERMS[w:lower()] then
				return put(w);
			end
			return w;
		end);
		return out, map;
	end
	local function unmask(text, map)
		return (text:gsub("{{%s*(%d+)%s*}}", function(i)
			return map[tonumber(i)] or "";
		end));
	end
	local LATIN_FOLD = {["\xC3\x80"]="A",["\xC3\x81"]="A",["\xC3\x82"]="A",["\xC3\x83"]="A",["\xC3\x84"]="A",["\xC3\x85"]="A",["\xC3\x86"]="AE",["\xC3\x87"]="C",["\xC3\x88"]="E",["\xC3\x89"]="E",["\xC3\x8A"]="E",["\xC3\x8B"]="E",["\xC3\x8C"]="I",["\xC3\x8D"]="I",["\xC3\x8E"]="I",["\xC3\x8F"]="I",["\xC3\x90"]="D",["\xC3\x91"]="N",["\xC3\x92"]="O",["\xC3\x93"]="O",["\xC3\x94"]="O",["\xC3\x95"]="O",["\xC3\x96"]="O",["\xC3\x98"]="O",["\xC3\x99"]="U",["\xC3\x9A"]="U",["\xC3\x9B"]="U",["\xC3\x9C"]="U",["\xC3\x9D"]="Y",["\xC3\x9F"]="ss",["\xC3\xA0"]="a",["\xC3\xA1"]="a",["\xC3\xA2"]="a",["\xC3\xA3"]="a",["\xC3\xA4"]="a",["\xC3\xA5"]="a",["\xC3\xA6"]="ae",["\xC3\xA7"]="c",["\xC3\xA8"]="e",["\xC3\xA9"]="e",["\xC3\xAA"]="e",["\xC3\xAB"]="e",["\xC3\xAC"]="i",["\xC3\xAD"]="i",["\xC3\xAE"]="i",["\xC3\xAF"]="i",["\xC3\xB0"]="d",["\xC3\xB1"]="n",["\xC3\xB2"]="o",["\xC3\xB3"]="o",["\xC3\xB4"]="o",["\xC3\xB5"]="o",["\xC3\xB6"]="o",["\xC3\xB8"]="o",["\xC3\xB9"]="u",["\xC3\xBA"]="u",["\xC3\xBB"]="u",["\xC3\xBC"]="u",["\xC3\xBD"]="y",["\xC3\xBF"]="y",["\xC4\x80"]="A",["\xC4\x81"]="a",["\xC4\x82"]="A",["\xC4\x83"]="a",["\xC4\x84"]="A",["\xC4\x85"]="a",["\xC4\x86"]="C",["\xC4\x87"]="c",["\xC4\x8C"]="C",["\xC4\x8D"]="c",["\xC4\x8E"]="D",["\xC4\x8F"]="d",["\xC4\x90"]="D",["\xC4\x91"]="d",["\xC4\x92"]="E",["\xC4\x93"]="e",["\xC4\x98"]="E",["\xC4\x99"]="e",["\xC4\x9A"]="E",["\xC4\x9B"]="e",["\xC4\x9E"]="G",["\xC4\x9F"]="g",["\xC4\xB0"]="I",["\xC4\xB1"]="i",["\xC5\x81"]="L",["\xC5\x82"]="l",["\xC5\x83"]="N",["\xC5\x84"]="n",["\xC5\x87"]="N",["\xC5\x88"]="n",["\xC5\x90"]="O",["\xC5\x91"]="o",["\xC5\x92"]="OE",["\xC5\x93"]="oe",["\xC5\x94"]="R",["\xC5\x95"]="r",["\xC5\x98"]="R",["\xC5\x99"]="r",["\xC5\x9A"]="S",["\xC5\x9B"]="s",["\xC5\x9E"]="S",["\xC5\x9F"]="s",["\xC5\xA0"]="S",["\xC5\xA1"]="s",["\xC5\xA2"]="T",["\xC5\xA3"]="t",["\xC5\xA4"]="T",["\xC5\xA5"]="t",["\xC5\xAA"]="U",["\xC5\xAB"]="u",["\xC5\xAE"]="U",["\xC5\xAF"]="u",["\xC5\xB0"]="U",["\xC5\xB1"]="u",["\xC5\xB9"]="Z",["\xC5\xBA"]="z",["\xC5\xBB"]="Z",["\xC5\xBC"]="z",["\xC5\xBD"]="Z",["\xC5\xBE"]="z",["\xC8\x99"]="s",["\xC8\x98"]="S",["\xC8\x9B"]="t",["\xC8\x9A"]="T"};
	local function fold_latin(s)
		return (s:gsub("[\xC3\xC4\xC5\xC8][\x80-\xBF]", LATIN_FOLD));
	end
	function chat(txt)
		if ((my_lang == "RO") or (server_lang == "RO")) then
			txt = ro_fold_ascii(txt);
		end
		if ((txt:find("\xD0[\x80-\xBF]") or txt:find("\xD1[\x80-\x8F]")) and _CONV_U8_TO_CP1251) then
			local r = _CONV_U8_TO_CP1251:iconv(txt);
			if (r and (r ~= "")) then
				txt = r;
			end
		elseif ((isCE(my_lang) or isCE(server_lang)) and _CONV_U8_TO_CP1250) then
			txt = normalize_ro(txt);
			local r = _CONV_U8_TO_CP1250:iconv(txt);
			if (r and (r ~= "")) then
				txt = r;
			end
		elseif ((txt:find("\xC3[\x80-\xBF]") or txt:find("\xC2[\x80-\xBF]")) and _CONV_U8_TO_CP1252) then
			local r = _CONV_U8_TO_CP1252:iconv(txt);
			if (r and (r ~= "")) then
				txt = r;
			end
		end
		sampAddChatMessage(txt, -1);
	end
	local glyph_ranges;
	local ui_icon_textures = {};
	local function ui_icon_file(name)
		return getWorkingDirectory() .. "\\resource\\translator-ultimate\\icons\\" .. name .. ".png";
	end
	imgui.OnInitialize(function()
		local imgui_io = imgui.GetIO();
		glyph_ranges = ffi.new("ImWchar[11]", {32,255,256,383,384,591,1024,1327,8364,8364,0});
		imgui_io.Fonts:AddFontFromFileTTF(getFolderPath(20) .. "\\arial.ttf", 14, nil, glyph_ranges);
		for _, name in ipairs({"message-circle","language","palette","help-circle","user-circle","messages","layout-dashboard","user-scan","box","keyboard"}) do
			local file = ui_icon_file(name);
			if doesFileExist(file) then
				local ok, texture = pcall(imgui.CreateTextureFromFile, file);
				if (ok and texture) then
					ui_icon_textures[name] = texture;
				end
			end
		end
		local style = imgui.GetStyle();
		style.WindowRounding, style.FrameRounding, style.ChildRounding = 10, 6, 8;
		style.WindowTitleAlign = imgui.ImVec2(0.5, 0.5);
		style.WindowPadding = imgui.ImVec2(14, 14);
		style.ItemSpacing = imgui.ImVec2(8, 8);
	end);
	local function applyTheme()
		local style = imgui.GetStyle();
		local colors = style.Colors;
		local r, g, b = mainCfg.theme.custom_r, mainCfg.theme.custom_g, mainCfg.theme.custom_b;
		if mainCfg.theme.auto_color then
			local money_color = memory.getuint32(12235312, false);
			b = bit.band(money_color, 255) / 255;
			g = bit.band(bit.rshift(money_color, 8), 255) / 255;
			r = bit.band(bit.rshift(money_color, 16), 255) / 255;
		end
		colors[imgui.Col.WindowBg] = imgui.ImVec4(0.1, 0.1, 0.12, 0.95);
		colors[imgui.Col.TitleBg] = imgui.ImVec4(0.12, 0.12, 0.14, 1);
		colors[imgui.Col.TitleBgActive] = imgui.ImVec4(r, g, b, 1);
		colors[imgui.Col.Button] = imgui.ImVec4(r, g, b, 1);
		colors[imgui.Col.ButtonHovered] = imgui.ImVec4(r * 1.2, g * 1.2, b * 1.2, 1);
		colors[imgui.Col.ButtonActive] = imgui.ImVec4(r * 0.8, g * 0.8, b * 0.8, 1);
		colors[imgui.Col.Header] = imgui.ImVec4(r, g, b, 1);
		colors[imgui.Col.HeaderHovered] = imgui.ImVec4(r * 1.2, g * 1.2, b * 1.2, 1);
		colors[imgui.Col.HeaderActive] = imgui.ImVec4(r * 0.8, g * 0.8, b * 0.8, 1);
		colors[imgui.Col.CheckMark] = imgui.ImVec4(r, g, b, 1);
		colors[imgui.Col.SliderGrab] = imgui.ImVec4(r, g, b, 1);
		colors[imgui.Col.SliderGrabActive] = imgui.ImVec4(r * 0.8, g * 0.8, b * 0.8, 1);
		colors[imgui.Col.FrameBg] = imgui.ImVec4(r * 0.3, g * 0.3, b * 0.3, 1);
		colors[imgui.Col.FrameBgHovered] = imgui.ImVec4(r * 0.4, g * 0.4, b * 0.4, 1);
		colors[imgui.Col.FrameBgActive] = imgui.ImVec4(r * 0.5, g * 0.5, b * 0.5, 1);
		colors[imgui.Col.TextSelectedBg] = imgui.ImVec4(r, g, b, 0.35);
	end
	local SAFE_LANGUAGE_NAMES = {ES="Spanish",["PT-BR"]="Portuguese",["EN-US"]="English",RU="Russian",PL="Polish",ID="Indonesian",TR="Turkish",CS="Czech (Czech Republic)",RO="Romanian",AUTO="Automatic"};
	local function safe_language_name(id)
		return SAFE_LANGUAGE_NAMES[id] or id;
	end
	local UI_BASE = {nav_translate="TRANSLATE",nav_languages="LANGUAGES",nav_appearance="COLORS",nav_faq="FAQ",nav_credits="CREDITS",headline="Translation controls",languages_title="Languages",display_lang="Language to display",send_lang="Language to send",server_lang="Server text encoding",chat="Translate chat",menus="Translate menus",head="Above-head texts",text3d="3D texts",chat_desc="Server, player, and outgoing messages",menus_desc="Dialogs, HUD, and TextDraws",head_desc="Conversation bubbles",text3d_desc="World labels",chat_tip="Translates server messages, player chat, and your messages. Commands starting with / are not changed.",menus_tip="Translates dialogs, HUD menus, and TextDraws.",head_tip="Translates bubbles shown above players.",text3d_tip="Translates 3D labels for properties, jobs, and interactive points.",advanced="Advanced",clan="Clan messages only",clan_tip="Limits automatic chat translation to clan messages.",appearance_title="Colors",auto_col="Use dynamic HUD color",man_col="Accent color",save="Save changes",ready="Changes saved",pending="Unsaved changes",faq_title="Frequently asked questions",faq_chat="What does chat translate?",faq_auto="How does detection work?",faq_cache="Why is the first result slower?",faq_visual="What does each visual control cover?",faq_chat_text="It includes server notices, player chat, and normal outgoing messages. / commands are not modified.",faq_auto_text="The source language is detected per message. Server encoding only helps SA:MP characters be read correctly.",faq_cache_text="The first occurrence needs a request. Repeated text comes from the local cache and appears immediately.",faq_visual_text="Menus includes dialogs and TextDraws. Above-head includes bubbles. 3D texts controls world labels.",credits_title="Credits",created_by="Created by NauTaro",discord="Copy Discord",nav_hotkeys="HOTKEYS",hk_title="Keyboard hotkeys",hk_menu="Open / close the menu",hk_autotr="Toggle automatic translation",hk_capture="Press a key...",hk_off="Disabled",hk_clear="Remove",hk_hint="Click the button, then press the key you want. ESC cancels."};
	local UI_LOCALES = {ES={nav_translate="TRADUCIR",nav_languages="IDIOMAS",nav_appearance="COLORES",nav_credits="CREDITOS",headline="Control de traduccion",languages_title="Idiomas",display_lang="Idioma para ver",send_lang="Idioma para enviar",server_lang="Codificacion del servidor",chat="Traducir chat",menus="Traducir menus",head="Textos sobre la cabeza",text3d="Textos 3D",chat_desc="Servidor, jugadores y mensajes enviados",menus_desc="Dialogos, HUD y TextDraws",head_desc="Burbujas de conversacion",text3d_desc="Etiquetas del mundo",chat_tip="Traduce mensajes del servidor, jugadores y tus mensajes. Los comandos que comienzan por / no se cambian.",menus_tip="Traduce dialogos, menus HUD y TextDraws.",head_tip="Traduce burbujas que se muestran encima de jugadores.",text3d_tip="Traduce etiquetas 3D de propiedades, trabajos y puntos interactivos.",advanced="Avanzado",clan="Solo mensajes de clan",clan_tip="Limita el chat automatico a mensajes de clan.",appearance_title="Personalizacion de colores",auto_col="Usar color dinamico del HUD",man_col="Color de acento",save="Guardar cambios",ready="Cambios guardados",pending="Cambios sin guardar",faq_title="Preguntas frecuentes",faq_chat="Que traduce el chat?",faq_auto="Como funciona la deteccion?",faq_cache="Por que la primera vez tarda?",faq_visual="Que cubre cada control visual?",faq_chat_text="Incluye avisos del servidor, chat de jugadores y mensajes normales enviados. Los comandos / no se modifican.",faq_auto_text="El idioma se detecta por mensaje. La codificacion del servidor solo ayuda a leer correctamente los caracteres de SA:MP.",faq_cache_text="La primera vez requiere una consulta. Las repeticiones se leen desde la cache local para aparecer al instante.",faq_visual_text="Menus incluye dialogos y TextDraws. Sobre la cabeza incluye burbujas. Textos 3D controla etiquetas del mundo.",credits_title="Creditos",created_by="Creado por NauTaro",discord="Copiar Discord",nav_hotkeys="ATAJOS",hk_title="Atajos de teclado",hk_menu="Abrir / cerrar el menu",hk_autotr="Activar / desactivar traduccion automatica",hk_capture="Presiona una tecla...",hk_off="Desactivada",hk_clear="Quitar",hk_hint="Pulsa el boton y luego la tecla que quieras. ESC cancela."},["PT-BR"]={nav_translate="TRADUZIR",nav_languages="IDIOMAS",nav_appearance="CORES",nav_credits="CREDITOS",headline="Controles de traducao",languages_title="Idiomas",display_lang="Idioma para visualizar",send_lang="Idioma para enviar",server_lang="Codificacao do servidor",chat="Traduzir chat",menus="Traduzir menus",head="Textos acima da cabeca",text3d="Textos 3D",chat_desc="Servidor, jogadores e mensagens enviadas",menus_desc="Dialogos, HUD e TextDraws",head_desc="Baloes de conversa",text3d_desc="Etiquetas do mundo",chat_tip="Traduz mensagens do servidor, jogadores e as suas mensagens. Comandos iniciados por / nao sao alterados.",menus_tip="Traduz dialogos, menus HUD e TextDraws.",head_tip="Traduz os baloes mostrados acima dos jogadores.",text3d_tip="Traduz etiquetas 3D de propriedades, empregos e pontos interativos.",advanced="Avancado",clan="Somente mensagens de cla",clan_tip="Limita a traducao automatica a mensagens de cla.",appearance_title="Personalizacao de cores",auto_col="Usar cor dinamica do HUD",man_col="Cor de destaque",save="Salvar alteracoes",ready="Alteracoes salvas",pending="Alteracoes nao salvas",faq_title="Perguntas frequentes",faq_chat="O que o chat traduz?",faq_auto="Como funciona a deteccao?",faq_cache="Por que a primeira vez demora?",faq_visual="O que cada controle visual inclui?",faq_chat_text="Inclui avisos do servidor, chat de jogadores e mensagens normais enviadas. Comandos / nao sao modificados.",faq_auto_text="O idioma e detectado por mensagem. A codificacao do servidor ajuda a ler os caracteres do SA:MP.",faq_cache_text="A primeira ocorrencia precisa de uma consulta. Repeticoes usam a cache local e aparecem na hora.",faq_visual_text="Menus inclui dialogos e TextDraws. Acima da cabeca inclui baloes. Textos 3D controla etiquetas do mundo.",credits_title="Creditos",created_by="Criado por NauTaro",discord="Copiar Discord",nav_hotkeys="ATALHOS",hk_title="Atalhos de teclado",hk_menu="Abrir / fechar o menu",hk_autotr="Ativar / desativar traducao automatica",hk_capture="Pressione uma tecla...",hk_off="Desativada",hk_clear="Remover",hk_hint="Clique no botao e depois pressione a tecla desejada. ESC cancela."},RU={nav_translate="ПЕРЕВОД",nav_languages="ЯЗЫКИ",nav_appearance="ЦВЕТА",nav_credits="АВТОРЫ",headline="Настройки перевода",languages_title="Языки",display_lang="Язык интерфейса",send_lang="Язык отправки",server_lang="Кодировка сервера",chat="Перевод чата",menus="Перевод меню",head="Текст над головой",text3d="3D тексты",chat_desc="Сервер, игроки и ваши сообщения",menus_desc="Диалоги, HUD и TextDraws",head_desc="Облака разговора",text3d_desc="Метки мира",chat_tip="Переводит сообщения сервера, игроков и ваши сообщения. Команды / не изменяются.",menus_tip="Переводит диалоги, HUD и TextDraws.",head_tip="Переводит текст над игроками.",text3d_tip="Переводит 3D метки мира, работ и объектов.",advanced="Дополнительно",clan="Только сообщения клана",clan_tip="Ограничивает перевод сообщениями клана.",appearance_title="Настройка цветов",auto_col="Цвет из HUD",man_col="Цвет акцента",save="Сохранить изменения",ready="Изменения сохранены",pending="Есть несохраненные изменения",faq_title="Частые вопросы",faq_chat="Что переводит чат?",faq_auto="Как работает определение?",faq_cache="Почему первый раз дольше?",faq_visual="Что включает каждая опция?",faq_chat_text="Переводит уведомления сервера, чат игроков и обычные исходящие сообщения. Команды / не изменяются.",faq_auto_text="Язык определяется для каждого сообщения. Кодировка помогает SA:MP правильно читать символы.",faq_cache_text="Первый текст требует запроса. Повторы берутся из локального кеша.",faq_visual_text="Меню включает диалоги и TextDraws. Над головой - облака. 3D - метки мира.",credits_title="Авторы",created_by="Создано NauTaro",discord="Копировать Discord",nav_hotkeys="КЛАВИШИ",hk_title="Горячие клавиши",hk_menu="Открыть / закрыть меню",hk_autotr="Вкл / выкл авто-перевод",hk_capture="Нажмите клавишу...",hk_off="Отключена",hk_clear="Убрать",hk_hint="Нажмите кнопку, затем клавишу. ESC - отмена."},PL={nav_translate="TLUMACZ",nav_languages="JEZYKI",nav_appearance="KOLORY",nav_credits="AUTOR",headline="Ustawienia tlumaczenia",languages_title="Jezyki",display_lang="Jezyk wyswietlania",send_lang="Jezyk wysylania",server_lang="Kodowanie serwera",chat="Tlumacz chat",menus="Tlumacz menu",head="Tekst nad glowa",text3d="Teksty 3D",chat_desc="Serwer, gracze i wiadomosci",menus_desc="Dialogi, HUD i TextDraws",head_desc="Dymki rozmow",text3d_desc="Etykiety swiata",chat_tip="Tlumaczy wiadomosci serwera, graczy i twoje wiadomosci. Komendy / nie sa zmieniane.",menus_tip="Tlumaczy dialogi, HUD i TextDraws.",head_tip="Tlumaczy dymki nad graczami.",text3d_tip="Tlumaczy etykiety 3D posiadlosci, prac i punktow.",advanced="Zaawansowane",clan="Tylko wiadomosci klanu",clan_tip="Ogranicza automatyczne tlumaczenie do klanu.",appearance_title="Personalizacja kolorow",auto_col="Uzyj dynamicznego koloru HUD",man_col="Kolor akcentu",save="Zapisz zmiany",ready="Zmiany zapisane",pending="Niezapisane zmiany",faq_title="Czesto zadawane pytania",faq_chat="Co tlumaczy chat?",faq_auto="Jak dziala wykrywanie?",faq_cache="Dlaczego pierwszy wynik trwa dluzej?",faq_visual="Co obejmuje kazda opcja?",faq_chat_text="Obejmuje komunikaty serwera, chat graczy i normalne wiadomosci. Komendy / nie sa zmieniane.",faq_auto_text="Jezyk jest wykrywany dla kazdej wiadomosci. Kodowanie pomaga SA:MP poprawnie odczytac znaki.",faq_cache_text="Pierwsze wystapienie wymaga zapytania. Powtorzenia sa pobierane z lokalnej pamieci cache.",faq_visual_text="Menu obejmuje dialogi i TextDraws. Nad glowa obejmuje dymki. Teksty 3D kontroluja etykiety swiata.",credits_title="Autor",created_by="Stworzone przez NauTaro",discord="Kopiuj Discord",nav_hotkeys="SKROTY",hk_title="Skroty klawiszowe",hk_menu="Otworz / zamknij menu",hk_autotr="Wlacz / wylacz automatyczne tlumaczenie",hk_capture="Nacisnij klawisz...",hk_off="Wylaczona",hk_clear="Usun",hk_hint="Kliknij przycisk, a potem nacisnij klawisz. ESC anuluje."},ID={nav_translate="TERJEMAHKAN",nav_languages="BAHASA",nav_appearance="WARNA",nav_credits="KREDIT",headline="Kontrol terjemahan",languages_title="Bahasa",display_lang="Bahasa tampilan",send_lang="Bahasa kirim",server_lang="Kode teks server",chat="Terjemahkan chat",menus="Terjemahkan menu",head="Teks di atas kepala",text3d="Teks 3D",chat_desc="Server, pemain, dan pesan terkirim",menus_desc="Dialog, HUD, dan TextDraws",head_desc="Gelembung percakapan",text3d_desc="Label dunia",chat_tip="Menerjemahkan pesan server, chat pemain, dan pesan Anda. Perintah / tidak diubah.",menus_tip="Menerjemahkan dialog, menu HUD, dan TextDraws.",head_tip="Menerjemahkan gelembung di atas pemain.",text3d_tip="Menerjemahkan label 3D properti, pekerjaan, dan titik interaktif.",advanced="Lanjutan",clan="Hanya pesan klan",clan_tip="Membatasi terjemahan chat otomatis ke pesan klan.",appearance_title="Personalisasi warna",auto_col="Gunakan warna HUD dinamis",man_col="Warna aksen",save="Simpan perubahan",ready="Perubahan tersimpan",pending="Perubahan belum disimpan",faq_title="Pertanyaan umum",faq_chat="Apa yang diterjemahkan chat?",faq_auto="Bagaimana deteksi bekerja?",faq_cache="Mengapa hasil pertama lebih lambat?",faq_visual="Apa cakupan tiap kontrol?",faq_chat_text="Mencakup pemberitahuan server, chat pemain, dan pesan normal. Perintah / tidak diubah.",faq_auto_text="Bahasa sumber dideteksi per pesan. Kode server hanya membantu SA:MP membaca karakter dengan benar.",faq_cache_text="Kemunculan pertama memerlukan permintaan. Teks berulang muncul dari cache lokal.",faq_visual_text="Menu mencakup dialog dan TextDraws. Atas kepala mencakup gelembung. Teks 3D mengatur label dunia.",credits_title="Kredit",created_by="Dibuat oleh NauTaro",discord="Salin Discord",nav_hotkeys="PINTASAN",hk_title="Pintasan keyboard",hk_menu="Buka / tutup menu",hk_autotr="Aktif / nonaktif terjemahan otomatis",hk_capture="Tekan tombol...",hk_off="Nonaktif",hk_clear="Hapus",hk_hint="Klik tombol lalu tekan tombol yang diinginkan. ESC membatalkan."},TR={nav_translate="CEVIRI",nav_languages="DILLER",nav_appearance="RENKLER",nav_credits="KREDILER",headline="Ceviri kontrolleri",languages_title="Diller",display_lang="Goruntulenecek dil",send_lang="Gonderme dili",server_lang="Sunucu metin kodlamasi",chat="Sohbeti cevir",menus="Menuleri cevir",head="Bas ustu metinler",text3d="3D metinler",chat_desc="Sunucu, oyuncu ve giden mesajlar",menus_desc="Diyaloglar, HUD ve TextDraws",head_desc="Konusma balonlari",text3d_desc="Dunya etiketleri",chat_tip="Sunucu mesajlarini, oyuncu sohbetini ve mesajlarinizi cevirir. / komutlari degistirilmez.",menus_tip="Diyaloglari, HUD menulerini ve TextDraws metinlerini cevirir.",head_tip="Oyuncularin ustundeki balonlari cevirir.",text3d_tip="Mulk, is ve etkilesimli noktalardaki 3D etiketleri cevirir.",advanced="Gelismis",clan="Yalnizca klan mesajlari",clan_tip="Otomatik sohbet cevirisini klan mesajlariyla sinirlar.",appearance_title="Renk kisilestirme",auto_col="Dinamik HUD rengini kullan",man_col="Vurgu rengi",save="Degisiklikleri kaydet",ready="Degisiklikler kaydedildi",pending="Kaydedilmemis degisiklikler",faq_title="Sik sorulan sorular",faq_chat="Sohbet neyi cevirir?",faq_auto="Algilama nasil calisir?",faq_cache="Ilk sonuc neden daha yavas?",faq_visual="Her kontrol neyi kapsar?",faq_chat_text="Sunucu bildirimlerini, oyuncu sohbetini ve normal giden mesajlari icerir. / komutlari degistirilmez.",faq_auto_text="Kaynak dil her mesaj icin algilanir. Sunucu kodlamasi SA:MP karakterlerinin okunmasina yardim eder.",faq_cache_text="Ilk gorunum bir istek gerektirir. Tekrarlar yerel onbellekten hemen gelir.",faq_visual_text="Menuler diyaloglari ve TextDraws metinlerini kapsar. Bas ustu balonlari kapsar. 3D metinler dunya etiketlerini kontrol eder.",credits_title="Krediler",created_by="NauTaro tarafindan olusturuldu",discord="Discord kopyala",nav_hotkeys="KISAYOLLAR",hk_title="Klavye kisayollari",hk_menu="Menuyu ac / kapat",hk_autotr="Otomatik ceviriyi ac / kapat",hk_capture="Bir tus basin...",hk_off="Kapali",hk_clear="Kaldir",hk_hint="Dugmeye tiklayin, sonra istediginiz tusa basin. ESC iptal eder."},CS={nav_translate="PREKLAD",nav_languages="JAZYKY",nav_appearance="BARVY",nav_credits="KREDITY",headline="Ovladani prekladu",languages_title="Jazyky",display_lang="Jazyk zobrazeni",send_lang="Jazyk odeslani",server_lang="Kodovani textu serveru",chat="Prekladat chat",menus="Prekladat menu",head="Text nad hlavou",text3d="3D texty",chat_desc="Server, hraci a odeslane zpravy",menus_desc="Dialogy, HUD a TextDraws",head_desc="Bubliny konverzace",text3d_desc="Popisky sveta",chat_tip="Preklada zpravy serveru, chat hracu a vase zpravy. Prikazy / se nemeni.",menus_tip="Preklada dialogy, HUD menu a TextDraws.",head_tip="Preklada bubliny nad hraci.",text3d_tip="Preklada 3D popisky majetku, praci a interaktivnich bodu.",advanced="Pokrocile",clan="Pouze zpravy klanu",clan_tip="Omezi automaticky preklad chatu na zpravy klanu.",appearance_title="Prizpusobeni barev",auto_col="Pouzit dynamickou barvu HUD",man_col="Barva zvyrazneni",save="Ulozit zmeny",ready="Zmeny ulozeny",pending="Neulozene zmeny",faq_title="Caste dotazy",faq_chat="Co preklada chat?",faq_auto="Jak funguje detekce?",faq_cache="Proc je prvni vysledek pomalejsi?",faq_visual="Co zahrnuje kazda volba?",faq_chat_text="Zahrnuje oznameni serveru, chat hracu a bezne odeslane zpravy. Prikazy / se nemeni.",faq_auto_text="Zdrojovy jazyk je zisten pro kazdou zpravu. Kodovani serveru pomaha SA:MP spravne cist znaky.",faq_cache_text="Prvni vyskyt vyzaduje pozadavek. Opakovany text se nacte z lokalni cache.",faq_visual_text="Menu zahrnuje dialogy a TextDraws. Nad hlavou zahrnuje bubliny. 3D texty ovladaji popisky sveta.",credits_title="Kredity",created_by="Vytvoril NauTaro",discord="Kopirovat Discord",nav_hotkeys="KLAVESY",hk_title="Klavesove zkratky",hk_menu="Otevrit / zavrit menu",hk_autotr="Zap / vyp automaticky preklad",hk_capture="Stisknete klavesu...",hk_off="Vypnuta",hk_clear="Odebrat",hk_hint="Kliknete na tlacitko a stisknete klavesu. ESC zrusi."},RO={nav_translate="TRADUCERE",nav_languages="LIMBI",nav_appearance="CULORI",nav_credits="CREDITE",headline="Control traducere",languages_title="Limbi",display_lang="Limba de afisare",send_lang="Limba de trimitere",server_lang="Codare text server",chat="Tradu chatul",menus="Tradu meniurile",head="Texte deasupra capului",text3d="Texte 3D",chat_desc="Server, jucatori si mesaje trimise",menus_desc="Dialoguri, HUD si TextDraws",head_desc="Bule de conversatie",text3d_desc="Etichete din lume",chat_tip="Traduce mesajele serverului, chatul jucatorilor si mesajele tale. Comenzile / nu sunt modificate.",menus_tip="Traduce dialoguri, meniuri HUD si TextDraws.",head_tip="Traduce bulele de deasupra jucatorilor.",text3d_tip="Traduce etichete 3D pentru proprietati, joburi si puncte interactive.",advanced="Avansat",clan="Doar mesaje de clan",clan_tip="Limiteaza traducerea automata la mesajele de clan.",appearance_title="Personalizare culori",auto_col="Foloseste culoarea dinamica HUD",man_col="Culoare accent",save="Salveaza modificarile",ready="Modificarile au fost salvate",pending="Modificari nesalvate",faq_title="Intrebari frecvente",faq_chat="Ce traduce chatul?",faq_auto="Cum functioneaza detectarea?",faq_cache="De ce primul rezultat e mai lent?",faq_visual="Ce include fiecare control?",faq_chat_text="Include anunturi de server, chatul jucatorilor si mesajele normale. Comenzile / nu se modifica.",faq_auto_text="Limba sursa este detectata pentru fiecare mesaj. Codarea serverului ajuta SA:MP sa citeasca corect caracterele.",faq_cache_text="Prima aparitie necesita o cerere. Repetitiile apar imediat din cache-ul local.",faq_visual_text="Meniurile includ dialoguri si TextDraws. Deasupra capului include bule. Textele 3D controleaza etichetele lumii.",credits_title="Credite",created_by="Creat de NauTaro",discord="Copiaza Discord",nav_hotkeys="SCURTATURI",hk_title="Scurtaturi de tastatura",hk_menu="Deschide / inchide meniul",hk_autotr="Activeaza / dezactiveaza traducerea automata",hk_capture="Apasa o tasta...",hk_off="Dezactivata",hk_clear="Scoate",hk_hint="Apasa butonul, apoi tasta dorita. ESC anuleaza."}};
		local UI_CHAT_MODES = {
			ES={chat_mode_title="Traducción del chat",chat_mode_hint="Elige cómo se traducen los mensajes de otros jugadores en el chat.",chat_auto="Reemplazar texto",chat_auto_desc="Solo verás la traducción. El original se oculta.",chat_auto_tip="Oculta el mensaje original del jugador y lo reemplaza directamente por su traducción. También traduce menus, dialogs, textdraws, textos 3D y burbujas.",chat_messages="Traducción debajo",chat_messages_desc="Verás el original y debajo la traducción.",chat_messages_tip="Mantiene el mensaje original del jugador intacto. Debajo añade su nombre en verde y la traducción [Auto-TR]. Ideal para servidores RP donde quieres leer el original.",other_texts="Otros textos del juego"},
			["PT-BR"]={chat_mode_title="Tradução do chat",chat_mode_hint="Escolha como as mensagens dos jogadores são traduzidas.",chat_auto="Substituir texto",chat_auto_desc="Apenas a tradução. Original oculto.",chat_auto_tip="Oculta a mensagem original do jogador e a substitui pela tradução. Também traduz menus, dialogs, textdraws, textos 3D e balões.",chat_messages="Tradução abaixo",chat_messages_desc="Original visível + tradução embaixo.",chat_messages_tip="Mantém a mensagem original do jogador intacta. Embaixo adiciona o nome em verde e a tradução [Auto-TR]. Ideal para servidores RP.",other_texts="Outros textos do jogo"},
			["EN-US"]={chat_mode_title="Chat translation",chat_mode_hint="Choose how other players' messages appear in the chat.",chat_auto="Replace text",chat_auto_desc="Only the translation. Original hidden.",chat_auto_tip="Hides the player's original message and replaces it with the translation. Also translates menus, dialogs, textdraws, 3D texts and bubbles.",chat_messages="Translation below",chat_messages_desc="Original visible + translation underneath.",chat_messages_tip="Keeps the player's original message intact. Below it, adds their name in green with the [Auto-TR] translation. Great for RP servers where you want to read the original.",other_texts="Other game texts"},
			RU={chat_mode_title="Перевод чата",chat_mode_hint="Выберите, как отображаются переведённые сообщения.",chat_auto="Замена текста",chat_auto_desc="Только перевод. Оригинал скрыт.",chat_auto_tip="Скрывает оригинальное сообщение игрока и заменяет его переводом. Также переводит меню, диалоги, текстдравы, 3D-тексты и пузыри.",chat_messages="Перевод ниже",chat_messages_desc="Оригинал виден + перевод внизу.",chat_messages_tip="Сохраняет оригинальное сообщение игрока. Ниже добавляет имя зелёным цветом и перевод [Auto-TR]. Удобно для RP-серверов.",other_texts="Другие игровые тексты"},
			PL={chat_mode_title="Tłumaczenie czatu",chat_mode_hint="Wybierz, jak wyświetlać tłumaczone wiadomości graczy.",chat_auto="Zastąp tekst",chat_auto_desc="Tylko tłumaczenie. Oryginał ukryty.",chat_auto_tip="Ukrywa oryginalną wiadomość gracza i zastępuje ją tłumaczeniem. Tłumaczy też menu, dialogi, textdrawy, teksty 3D i dymki.",chat_messages="Tłumaczenie poniżej",chat_messages_desc="Oryginał widoczny + tłumaczenie poniżej.",chat_messages_tip="Zachowuje oryginalną wiadomość gracza. Poniżej dodaje jego imię na zielono i tłumaczenie [Auto-TR]. Przydatne na serwerach RP.",other_texts="Inne teksty gry"},
			ID={chat_mode_title="Terjemahan chat",chat_mode_hint="Pilih bagaimana pesan pemain lain diterjemahkan.",chat_auto="Ganti teks",chat_auto_desc="Hanya terjemahan. Asli disembunyikan.",chat_auto_tip="Menyembunyikan pesan asli pemain dan menggantinya dengan terjemahan. Juga menerjemahkan menu, dialog, textdraw, teks 3D dan gelembung.",chat_messages="Terjemahan di bawah",chat_messages_desc="Asli terlihat + terjemahan di bawahnya.",chat_messages_tip="Mempertahankan pesan asli pemain. Di bawahnya menambahkan namanya berwarna hijau dan terjemahan [Auto-TR]. Cocok untuk server RP.",other_texts="Teks game lainnya"},
			TR={chat_mode_title="Sohbet çevirisi",chat_mode_hint="Diğer oyuncuların mesajları nasıl görünsün.",chat_auto="Metni değiştir",chat_auto_desc="Sadece çeviri. Orijinal gizli.",chat_auto_tip="Oyuncunun orijinal mesajını gizler ve çeviriyle değiştirir. Ayrıca menüleri, diyalogları, textdrawları, 3D metinlerini ve baloncukları çevirir.",chat_messages="Çeviri aşağıda",chat_messages_desc="Orijinal görünür + çeviri aşağıda.",chat_messages_tip="Oyuncunun orijinal mesajını korur. Altına yeşil renkte adını ve [Auto-TR] çevirisini ekler. RP sunucuları için ideal.",other_texts="Diğer oyun metinleri"},
			CS={chat_mode_title="Překlad chatu",chat_mode_hint="Vyberte, jak se zobrazují překládané zprávy hráčů.",chat_auto="Nahradit text",chat_auto_desc="Pouze překlad. Originál skrytý.",chat_auto_tip="Skryje původní zprávu hráče a nahradí ji překladem. Také překládá menu, dialogy, textdrawy, 3D texty a bubliny.",chat_messages="Překlad níže",chat_messages_desc="Originál viditelný + překlad pod ním.",chat_messages_tip="Zachová původní zprávu hráče. Pod ní přidá jeho jméno zeleně a překlad [Auto-TR]. Ideální pro RP servery.",other_texts="Další texty hry"},
			RO={chat_mode_title="Traducere chat",chat_mode_hint="Alege cum apar mesajele traduse ale altor jucători.",chat_auto="Înlocuiește text",chat_auto_desc="Doar traducerea. Original ascuns.",chat_auto_tip="Ascunde mesajul original al jucătorului și îl înlocuiește cu traducerea. De asemenea traduce meniuri, dialoguri, textdrawuri, texte 3D și bule.",chat_messages="Traducere dedesubt",chat_messages_desc="Original vizibil + traducere dedesubt.",chat_messages_tip="Păstrează mesajul original al jucătorului. Dedesubt adaugă numele său în verde și traducerea [Auto-TR]. Ideal pentru servere RP.",other_texts="Alte texte ale jocului"}
		};
		local UI_OUT_TOGGLE = {
			ES={auto_out="Traducir automáticamente lo que escribo",auto_out_tip="Activado: todo lo que escribas se traduce antes de enviarse (verás [TR] Traduciendo... igual que con /tr). Desactivado: solo se traduce usando /tr.",auto_update="Buscar actualizaciones automáticamente",auto_update_tip="Al iniciar, comprueba silenciosamente si hay una versión nueva y la instala reiniciando el script. Si falla (sin internet o servidor caído), no pasa nada: el mod sigue funcionando con la versión actual."},
			["PT-BR"]={auto_out="Traduzir automaticamente o que eu escrevo",auto_out_tip="Ativado: tudo o que você escreve é traduzido antes do envio (verá [TR] Traduzindo... igual ao /tr). Desativado: traduz apenas com /tr.",auto_update="Buscar atualizações automaticamente",auto_update_tip="Ao iniciar, verifica silenciosamente se há uma versão nova e instala reiniciando o script. Se falhar, o mod continua na versão atual."},
			["EN-US"]={auto_out="Auto-translate what I type",auto_out_tip="On: everything you type is translated before sending (shows [TR] Translating... just like /tr). Off: only /tr is translated.",auto_update="Check for updates automatically",auto_update_tip="On startup, silently checks for a new version and installs it by reloading the script. On failure, the mod keeps running the current version."},
			RU={auto_out="Автоперевод моих сообщений",auto_out_tip="Вкл: всё, что вы пишете, переводится перед отправкой (показывает [TR] Перевод... как и /tr). Выкл: перевод только через /tr.",auto_update="Автоматически проверять обновления",auto_update_tip="При запуске незаметно проверяет новую версию и устанавливает её перезапуском скрипта. При сбое мод работает на текущей версии."},
			PL={auto_out="Automatycznie tłumacz to, co piszę",auto_out_tip="Wł.: wszystko co napiszesz jest tłumaczone przed wysłaniem (pokaże [TR] Tłumaczenie... jak /tr). Wył.: tłumaczy tylko /tr.",auto_update="Automatycznie sprawdzaj aktualizacje",auto_update_tip="Przy starcie po cichu sprawdza nową wersję i instaluje ją przeładowaniem skryptu. Przy błędzie mod działa na bieżącej wersji."},
			ID={auto_out="Terjemahkan otomatis yang saya tulis",auto_out_tip="Aktif: semua yang Anda tulis diterjemahkan sebelum dikirim (menampilkan [TR] Menerjemahkan... seperti /tr). Nonaktif: hanya /tr.",auto_update="Periksa pembaruan otomatis",auto_update_tip="Saat mulai, memeriksa versi baru secara diam-diam dan memasangnya dengan memuat ulang skrip. Jika gagal, mod tetap berjalan."},
			TR={auto_out="Yazdıklarımı otomatik çevir",auto_out_tip="Açık: yazdığınız her şey gönderilmeden önce çevrilir (/tr gibi [TR] Çevriliyor... gösterir). Kapalı: sadece /tr.",auto_update="Güncellemeleri otomatik kontrol et",auto_update_tip="Açılışta sessizce yeni sürümü kontrol eder ve betiği yeniden yükleyerek kurar. Başarısız olursa mod mevcut sürümde çalışır."},
			CS={auto_out="Automaticky překládat, co napíšu",auto_out_tip="Zapnuto: vše, co napíšete, se před odesláním přeloží (zobrazí [TR] Překládám... jako /tr). Vypnuto: překládá pouze /tr.",auto_update="Automaticky kontrolovat aktualizace",auto_update_tip="Při startu tiše zkontroluje novou verzi a nainstaluje ji opětovným načtením skriptu. Při selhání mod běží na aktuální verzi."},
			RO={auto_out="Tradu automat ce scriu",auto_out_tip="Activ: tot ce scrii este tradus înainte de trimitere (afișează [TR] Se traduce... ca /tr). Inactiv: traduce doar /tr.",auto_update="Verifică automat actualizări",auto_update_tip="La pornire, verifică discret o versiune nouă și o instalează reîncărcând scriptul. Dacă eșuează, modul rulează versiunea actuală."}
		};
		local function ui_strings()
		local out = {};
		for k, v in pairs(UI_BASE) do
			out[k] = v;
		end
		for k, v in pairs(UI_LOCALES[my_lang] or {}) do
			out[k] = v;
		end
		for k, v in pairs(UI_CHAT_MODES[my_lang] or UI_CHAT_MODES["EN-US"]) do
			out[k] = v;
		end
		for k, v in pairs(UI_OUT_TOGGLE[my_lang] or UI_OUT_TOGGLE["EN-US"]) do
			out[k] = v;
		end
		return out;
	end
	local function ui_accent()
		return 0.153, 0.961, 0.584;
	end
	local function ui_tooltip(text)
		if imgui.IsItemHovered() then
			imgui.BeginTooltip();
			imgui.PushTextWrapPos(330);
			imgui.TextUnformatted(text);
			imgui.PopTextWrapPos();
			imgui.EndTooltip();
		end
	end
	local function draw_feature_icon(kind, active)
		local p, dl = imgui.GetCursorScreenPos(), imgui.GetWindowDrawList();
		local r, g, b = ui_accent();
		local col = (active and imgui.U32(r, g, b, 1)) or imgui.U32(0.38, 0.45, 0.56, 1);
		local web_icons = {chat="messages",menu="layout-dashboard",head="user-scan",text3d="box"};
		local texture = ui_icon_textures[web_icons[kind]];
		if texture then
			dl:AddImage(texture, imgui.ImVec2(p.x + 3, p.y + 6), imgui.ImVec2(p.x + 23, p.y + 26), nil, nil, col);
			return;
		end
		local line = imgui.U32(0.84, 0.92, 1, 1);
		if (kind == "chat") then
			dl:AddRect(imgui.ImVec2(p.x + 4, p.y + 7), imgui.ImVec2(p.x + 20, p.y + 17), col, 3, 0, 1.5);
			dl:AddLine(imgui.ImVec2(p.x + 9, p.y + 17), imgui.ImVec2(p.x + 8, p.y + 21), col, 1.5);
			dl:AddCircleFilled(imgui.ImVec2(p.x + 9, p.y + 12), 1, line, 6);
			dl:AddCircleFilled(imgui.ImVec2(p.x + 13, p.y + 12), 1, line, 6);
			dl:AddCircleFilled(imgui.ImVec2(p.x + 17, p.y + 12), 1, line, 6);
		elseif (kind == "menu") then
			dl:AddRect(imgui.ImVec2(p.x + 4, p.y + 5), imgui.ImVec2(p.x + 20, p.y + 20), col, 2, 0, 1.5);
			dl:AddLine(imgui.ImVec2(p.x + 8, p.y + 10), imgui.ImVec2(p.x + 17, p.y + 10), line, 1);
			dl:AddLine(imgui.ImVec2(p.x + 8, p.y + 14), imgui.ImVec2(p.x + 17, p.y + 14), line, 1);
		elseif (kind == "head") then
			dl:AddCircle(imgui.ImVec2(p.x + 12, p.y + 9), 4, col, 12, 1.5);
			dl:AddLine(imgui.ImVec2(p.x + 5, p.y + 20), imgui.ImVec2(p.x + 19, p.y + 20), col, 2);
			dl:AddLine(imgui.ImVec2(p.x + 12, p.y + 13), imgui.ImVec2(p.x + 12, p.y + 19), col, 1.5);
			dl:AddRect(imgui.ImVec2(p.x + 17, p.y + 4), imgui.ImVec2(p.x + 23, p.y + 9), line, 2, 0, 1);
		else
			dl:AddRect(imgui.ImVec2(p.x + 5, p.y + 7), imgui.ImVec2(p.x + 18, p.y + 20), col, 2, 0, 1.5);
			dl:AddLine(imgui.ImVec2(p.x + 5, p.y + 7), imgui.ImVec2(p.x + 11, p.y + 4), col, 1.5);
			dl:AddLine(imgui.ImVec2(p.x + 18, p.y + 7), imgui.ImVec2(p.x + 22, p.y + 11), col, 1.5);
			dl:AddLine(imgui.ImVec2(p.x + 18, p.y + 20), imgui.ImVec2(p.x + 22, p.y + 16), col, 1.5);
		end
	end
	local function nav_symbol(kind, p, col)
		local dl = imgui.GetWindowDrawList();
		local names = {chat="message-circle",lang="language",color="palette",faq="help-circle",user="user-circle"};
		local texture = ui_icon_textures[names[kind]];
		if texture then
			dl:AddImage(texture, imgui.ImVec2(p.x + 4, p.y + 5), imgui.ImVec2(p.x + 20, p.y + 21), nil, nil, col);
			return;
		end
		if (kind == "chat") then
			dl:AddRect(imgui.ImVec2(p.x + 5, p.y + 8), imgui.ImVec2(p.x + 18, p.y + 17), col, 3, 0, 1.5);
			dl:AddLine(imgui.ImVec2(p.x + 9, p.y + 17), imgui.ImVec2(p.x + 8, p.y + 20), col, 1.5);
			dl:AddCircleFilled(imgui.ImVec2(p.x + 9, p.y + 12), 1, col, 6);
			dl:AddCircleFilled(imgui.ImVec2(p.x + 12, p.y + 12), 1, col, 6);
			dl:AddCircleFilled(imgui.ImVec2(p.x + 15, p.y + 12), 1, col, 6);
		elseif (kind == "lang") then
			dl:AddCircle(imgui.ImVec2(p.x + 12, p.y + 13), 7, col, 12, 1.4);
			dl:AddLine(imgui.ImVec2(p.x + 5, p.y + 13), imgui.ImVec2(p.x + 19, p.y + 13), col, 1);
			dl:AddLine(imgui.ImVec2(p.x + 12, p.y + 6), imgui.ImVec2(p.x + 12, p.y + 20), col, 1);
			dl:AddCircle(imgui.ImVec2(p.x + 12, p.y + 13), 3.5, col, 12, 1);
		elseif (kind == "color") then
			dl:AddCircleFilled(imgui.ImVec2(p.x + 12, p.y + 13), 7, col, 12);
			dl:AddCircleFilled(imgui.ImVec2(p.x + 15, p.y + 10), 1.5, imgui.U32(0.08, 0.1, 0.14, 1), 8);
			dl:AddCircleFilled(imgui.ImVec2(p.x + 9, p.y + 10), 1, imgui.U32(0.08, 0.1, 0.14, 1), 8);
			dl:AddCircleFilled(imgui.ImVec2(p.x + 9, p.y + 15), 1, imgui.U32(0.08, 0.1, 0.14, 1), 8);
		elseif (kind == "faq") then
			dl:AddCircle(imgui.ImVec2(p.x + 12, p.y + 13), 7, col, 12, 1.4);
			dl:AddText(imgui.ImVec2(p.x + 9, p.y + 6), col, "?");
		elseif (kind == "keys") then
			dl:AddRect(imgui.ImVec2(p.x + 4, p.y + 6), imgui.ImVec2(p.x + 20, p.y + 18), col, 2, 0, 1.4);
			for row = 0, 2 do
				for k = 0, 7 do
					dl:AddRectFilled(imgui.ImVec2(p.x + 6 + (k * 1.8), p.y + 8 + (row * 3)), imgui.ImVec2(p.x + 7.2 + (k * 1.8), p.y + 9.6 + (row * 3)), col, 0);
				end
			end
			dl:AddRectFilled(imgui.ImVec2(p.x + 9, p.y + 17), imgui.ImVec2(p.x + 15, p.y + 18.4), col, 0);
		else
			dl:AddCircle(imgui.ImVec2(p.x + 12, p.y + 10), 4, col, 12, 1.4);
			dl:AddLine(imgui.ImVec2(p.x + 5, p.y + 21), imgui.ImVec2(p.x + 19, p.y + 21), col, 2);
			dl:AddLine(imgui.ImVec2(p.x + 12, p.y + 14), imgui.ImVec2(p.x + 12, p.y + 20), col, 1.4);
		end
	end
	local function nav_item(id, kind, label, selected)
		local p = imgui.GetCursorScreenPos();
		local clicked = imgui.Selectable("##nav_" .. id, selected, 0, imgui.ImVec2(0, 29));
		local r, g, b = ui_accent();
		local icon_col = (selected and imgui.U32(r, g, b, 1)) or imgui.U32(0.55, 0.62, 0.72, 1);
		nav_symbol(kind, p, icon_col);
		imgui.GetWindowDrawList():AddText(imgui.ImVec2(p.x + 25, p.y + 7), (selected and imgui.U32(0.92, 0.96, 1, 1)) or imgui.U32(0.72, 0.77, 0.84, 1), label);
		return clicked;
	end
	local function sync_feature_toggle(id, value)
		if (id == "chat_auto") then
			if value then
				chat_translation_mode, chat_tr_enabled = "automatic", true;
				chat_auto_cb[0], chat_messages_cb[0] = true, false;
			elseif (chat_translation_mode == "automatic") then
				chat_tr_enabled = false;
			end
			autotr_enabled = chat_tr_enabled;
		elseif (id == "chat_messages") then
			if value then
				chat_translation_mode, chat_tr_enabled = "messages", true;
				chat_auto_cb[0], chat_messages_cb[0] = false, true;
			elseif (chat_translation_mode == "messages") then
				chat_tr_enabled = false;
			end
			autotr_enabled = chat_tr_enabled;
		elseif (id == "menus") then
			menu_tr_enabled = value;
		elseif (id == "head") then
			head_tr_enabled = value;
		elseif (id == "text3d") then
			text3d_tr_enabled = value;
		end
	end
	local function feature_card(id, kind, title, description, tooltip, control)
		local active = control[0];
		local r, g, b = ui_accent();
		imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding, imgui.ImVec2(7, 2));
		imgui.PushStyleColor(imgui.Col.ChildBg, (active and imgui.ImVec4(0.055 + (r * 0.1), 0.065 + (g * 0.1), 0.085 + (b * 0.1), 1)) or imgui.ImVec4(0.075, 0.085, 0.105, 1));
		imgui.PushStyleColor(imgui.Col.Border, (active and imgui.ImVec4(r, g, b, 0.85)) or imgui.ImVec4(0.16, 0.19, 0.23, 1));
		imgui.BeginChild("tr_card_" .. id, imgui.ImVec2(0, 40), true, imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse);
		local width = imgui.GetContentRegionAvail().x;
		draw_feature_icon(kind, active);
		imgui.SetCursorPos(imgui.ImVec2(30, 2));
		imgui.TextColored((active and imgui.ImVec4(0.92, 0.96, 1, 1)) or imgui.ImVec4(0.72, 0.76, 0.82, 1), title);
		imgui.SetCursorPos(imgui.ImVec2(30, 19));
		imgui.TextColored(imgui.ImVec4(0.5, 0.58, 0.68, 1), description);
		imgui.SetCursorPos(imgui.ImVec2(width - 17, 7));
		if imgui.Checkbox("##feature_" .. id, control) then
			sync_feature_toggle(id, control[0]);
			config_dirty = true;
		end
		ui_tooltip(tooltip);
		imgui.EndChild();
		imgui.PopStyleColor(2);
		imgui.PopStyleVar();
	end
	local applied_server_key = nil;
	local lang_detect = {total=0, ru=0, ce=0, latin=0, done=false};
	local CE_BYTE_SET = {};
	do
		for _, b in ipairs({0x81,0x8C,0x8D,0x8F,0x9D,0x9F,0xA5,0xAC,0xAF,0xB1,0xB3,0xB9,0xBA,0xBC,0xBE,0xFE}) do
			CE_BYTE_SET[b] = true;
		end
	end
	local function server_key()
		if sampGetCurrentServerAddress then
			local ok, ip, port = pcall(sampGetCurrentServerAddress);
			if (ok and ip and (ip ~= "") and (ip ~= "127.0.0.1")) then
				return ip .. ":" .. tostring(port);
			end
		end
		return nil;
	end
	local function has_ce_bytes(text)
		for i = 1, #text do
			if CE_BYTE_SET[text:byte(i)] then
				return true;
			end
		end
		return false;
	end
	local function apply_server_profile()
		local key = server_key();
		if (key == applied_server_key) then
			return;
		end
		applied_server_key = key;
		lang_detect = {total=0, ru=0, ce=0, latin=0, done=false};
		local saved = key and mainCfg.servers[key:gsub("[%.:]", "_")];
		local target = ((saved and (get_lang_idx(saved) > 0)) and saved) or mainCfg.config.server_lang;
		if (target and (get_lang_idx(target) > 0)) then
			server_lang = target;
			srv_lang_idx[0] = get_lang_idx(target);
		end
	end
	local function detect_server_language(text)
		if ((server_lang ~= "AUTO") or lang_detect.done or (not text)) then
			return;
		end
		local hi, letters = 0, 0;
		for i = 1, #text do
			local b = text:byte(i);
			if (b >= 128) then
				hi = hi + 1;
				letters = letters + 1;
			elseif (((b >= 65) and (b <= 90)) or ((b >= 97) and (b <= 122))) then
				letters = letters + 1;
			end
		end
		if ((hi == 0) or (letters < 4)) then
			return;
		end
		lang_detect.total = lang_detect.total + 1;
		if looks_cyrillic(text) then
			lang_detect.ru = lang_detect.ru + 1;
		elseif has_ce_bytes(text) then
			lang_detect.ce = lang_detect.ce + 1;
		else
			lang_detect.latin = lang_detect.latin + 1;
		end
		if (lang_detect.total >= 15) then
			lang_detect.done = true;
			local detected = "EN-US";
			if ((lang_detect.ru > 0) and (lang_detect.ru >= lang_detect.ce) and (lang_detect.ru >= lang_detect.latin)) then
				detected = "RU";
			elseif ((lang_detect.ce > 0) and (lang_detect.ce > lang_detect.latin)) then
				detected = "PL";
			end
			server_lang = detected;
			srv_lang_idx[0] = get_lang_idx(detected);
			local key = server_key();
			if key then
				mainCfg.servers[key:gsub("[%.:]", "_")] = detected;
			end
			inicfg.save(mainCfg, iniFileName);
			chat("{27F595}[TR] {FFFFFF}Server encoding: " .. safe_language_name(detected));
		end
	end
	local refresh_menu_translations = nil;
	local applied_lang_state = my_lang .. "|" .. server_lang .. "|" .. tostring(menu_tr_enabled) .. "|" .. tostring(text3d_tr_enabled);
	local function save_translator_settings()
		mainCfg.config.my_lang = my_lang;
		mainCfg.config.out_lang = out_lang;
		mainCfg.config.server_lang = server_lang;
		mainCfg.config.translate_chat = chat_tr_enabled;
		mainCfg.config.chat_translation_mode = chat_translation_mode;
		mainCfg.config.translate_menus = menu_tr_enabled;
		mainCfg.config.translate_above_head = head_tr_enabled;
		mainCfg.config.translate_3d = text3d_tr_enabled;
		mainCfg.config.auto_translate_out = auto_out_enabled;
		mainCfg.config.auto_update = auto_update_enabled;
		mainCfg.config.auto_update_url = auto_update_url;
		mainCfg.config.menu_tr = menu_tr_enabled;
		local ok = inicfg.save(mainCfg, iniFileName);
		if ok then
			local skey = server_key();
			if skey then
				mainCfg.servers[skey:gsub("[%.:]", "_")] = server_lang;
				inicfg.save(mainCfg, iniFileName);
			end
			local state = my_lang .. "|" .. server_lang .. "|" .. tostring(menu_tr_enabled) .. "|" .. tostring(text3d_tr_enabled);
			if ((applied_lang_state ~= state) and refresh_menu_translations) then
				refresh_menu_translations();
			end
			applied_lang_state = state;
		end
		return ok;
	end
	local function language_selector(label, combo_id, index, max_items, on_pick)
		imgui.TextColored(imgui.ImVec4(0.58, 0.67, 0.78, 1), label);
		imgui.PushItemWidth(-1);
		if imgui.BeginCombo(combo_id, safe_language_name(lang_list[index[0] + 1].id)) then
			for i = 1, max_items do
				local selected = index[0] == (i - 1);
				if imgui.Selectable(safe_language_name(lang_list[i].id), selected) then
					index[0] = i - 1;
					on_pick(lang_list[i].id);
					config_dirty = true;
				end
			end
			imgui.EndCombo();
		end
		imgui.PopItemWidth();
	end
	local function ui_push_palette()
		local r, g, b = ui_accent();
		imgui.PushStyleColor(imgui.Col.TitleBg, imgui.ImVec4(0.035, 0.05, 0.075, 1));
		imgui.PushStyleColor(imgui.Col.TitleBgActive, imgui.ImVec4(0.035 + (r * 0.3), 0.05 + (g * 0.3), 0.075 + (b * 0.3), 1));
		imgui.PushStyleColor(imgui.Col.Header, imgui.ImVec4(r * 0.6, g * 0.6, b * 0.6, 0.85));
		imgui.PushStyleColor(imgui.Col.HeaderHovered, imgui.ImVec4(math.min(r + 0.1, 1), math.min(g + 0.1, 1), math.min(b + 0.1, 1), 0.95));
		imgui.PushStyleColor(imgui.Col.HeaderActive, imgui.ImVec4(r * 0.75, g * 0.75, b * 0.75, 1));
		imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(r * 0.78, g * 0.78, b * 0.78, 0.95));
		imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(math.min(r + 0.12, 1), math.min(g + 0.12, 1), math.min(b + 0.12, 1), 1));
		imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(r * 0.58, g * 0.58, b * 0.58, 1));
		imgui.PushStyleColor(imgui.Col.CheckMark, imgui.ImVec4(r, g, b, 1));
		imgui.PushStyleColor(imgui.Col.FrameBg, imgui.ImVec4(0.07, 0.1, 0.14, 1));
		imgui.PushStyleColor(imgui.Col.FrameBgHovered, imgui.ImVec4(0.08 + (r * 0.16), 0.1 + (g * 0.16), 0.14 + (b * 0.16), 1));
		imgui.PushStyleColor(imgui.Col.FrameBgActive, imgui.ImVec4(0.08 + (r * 0.24), 0.1 + (g * 0.24), 0.14 + (b * 0.24), 1));
	end
	local ui_capture_target = nil;
	local function vk_name(vk)
		if ((vk or 0) == 0) then
			return nil;
		end
		if ((vk >= 112) and (vk <= 123)) then
			return "F" .. (vk - 111);
		end
		if (((vk >= 65) and (vk <= 90)) or ((vk >= 48) and (vk <= 57))) then
			return string.char(vk);
		end
		return "#" .. vk;
	end
	local function current_vk(which)
		return (which == "menu") and hotkey_menu_vk or hotkey_auto_vk;
	end
	local function set_vk(which, vk)
		if (which == "menu") then
			hotkey_menu_vk, mainCfg.config.hotkey_menu = vk, vk;
		else
			hotkey_auto_vk, mainCfg.config.hotkey_auto = vk, vk;
		end
		inicfg.save(mainCfg, iniFileName);
	end
	local function hotkey_row(label, which, ux)
		imgui.TextColored(imgui.ImVec4(0.58, 0.67, 0.78, 1), label);
		local capturing = (ui_capture_target == which);
		local caption = (capturing and ux.hk_capture) or (vk_name(current_vk(which)) or ux.hk_off);
		if imgui.Button(caption .. "##hk_" .. which, imgui.ImVec2(170, 28)) then
			ui_capture_target = which;
		end
		imgui.SameLine();
		if imgui.Button(ux.hk_clear .. "##hkc_" .. which, imgui.ImVec2(90, 28)) then
			set_vk(which, 0);
			ui_capture_target = nil;
		end
		imgui.Spacing();
	end
	imgui.OnFrame(function()
		return menu_active[0];
	end, function()
		applyTheme();
		local ux = ui_strings();
		ui_push_palette();
		local r, g, b = ui_accent();
		local resX, resY = getScreenResolution();
		imgui.SetNextWindowPos(imgui.ImVec2(resX / 2, resY / 2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5));
		imgui.SetNextWindowSize(imgui.ImVec2(640, 460), imgui.Cond.Always);
		imgui.Begin("Translator Ultimate", menu_active, imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoResize);
		imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding, imgui.ImVec2(10, 10));
		imgui.BeginChild("tr_nav", imgui.ImVec2(126, 0), true, imgui.WindowFlags.NoScrollbar);
		imgui.TextColored(imgui.ImVec4(r, g, b, 1), "TR");
		imgui.SameLine();
		imgui.TextColored(imgui.ImVec4(0.78, 0.86, 0.96, 1), "ULTIMATE");
		imgui.Separator();
		if nav_item("translate", "chat", ux.nav_translate, current_tab[0] == 1) then
			current_tab[0] = 1;
		end
		if nav_item("languages", "lang", ux.nav_languages, current_tab[0] == 2) then
			current_tab[0] = 2;
		end
		if nav_item("appearance", "color", ux.nav_appearance, current_tab[0] == 3) then
			current_tab[0] = 3;
		end
		if nav_item("faq", "faq", ux.nav_faq, current_tab[0] == 4) then
			current_tab[0] = 4;
		end
		if nav_item("credits", "user", ux.nav_credits, current_tab[0] == 5) then
			current_tab[0] = 5;
		end
		if nav_item("hotkeys", "keys", ux.nav_hotkeys, current_tab[0] == 6) then
			current_tab[0] = 6;
		end
		imgui.EndChild();
		imgui.PopStyleVar();
		imgui.SameLine();
		imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding, imgui.ImVec2(10, 8));
		imgui.BeginChild("tr_main", imgui.ImVec2(0, 0), false, 0);
		if (current_tab[0] == 1) then
			chat_auto_cb[0] = chat_tr_enabled and (chat_translation_mode == "automatic");
			chat_messages_cb[0] = chat_tr_enabled and (chat_translation_mode == "messages");
			menu_tr_cb[0], head_tr_cb[0], text3d_tr_cb[0] = menu_tr_enabled, head_tr_enabled, text3d_tr_enabled;
			imgui.TextColored(imgui.ImVec4(0.88, 0.94, 1, 1), ux.chat_mode_title);
			imgui.TextColored(imgui.ImVec4(0.5, 0.58, 0.68, 1), ux.chat_mode_hint);
			imgui.Separator();
			feature_card("chat_auto", "chat", ux.chat_auto, ux.chat_auto_desc, ux.chat_auto_tip, chat_auto_cb);
				feature_card("chat_messages", "chat", ux.chat_messages, ux.chat_messages_desc, ux.chat_messages_tip, chat_messages_cb);
				auto_out_cb[0] = auto_out_enabled;
				if imgui.Checkbox(ux.auto_out, auto_out_cb) then
					auto_out_enabled = auto_out_cb[0];
					config_dirty = true;
				end
				ui_tooltip(ux.auto_out_tip);
				imgui.Spacing();
			imgui.TextColored(imgui.ImVec4(0.58, 0.67, 0.78, 1), ux.other_texts);
			imgui.Separator();
			feature_card("menus", "menu", ux.menus, ux.menus_desc, ux.menus_tip, menu_tr_cb);
			feature_card("head", "head", ux.head, ux.head_desc, ux.head_tip, head_tr_cb);
			feature_card("text3d", "text3d", ux.text3d, ux.text3d_desc, ux.text3d_tip, text3d_tr_cb);
			imgui.Spacing();
			imgui.TextColored(imgui.ImVec4(0.58, 0.67, 0.78, 1), ux.advanced);
			only_clan_cb[0] = only_clan;
			if imgui.Checkbox(ux.clan, only_clan_cb) then
				only_clan = only_clan_cb[0];
			end
			ui_tooltip(ux.clan_tip);
			auto_update_cb[0] = auto_update_enabled;
			if imgui.Checkbox(ux.auto_update, auto_update_cb) then
				auto_update_enabled = auto_update_cb[0];
				config_dirty = true;
			end
			ui_tooltip(ux.auto_update_tip);
		elseif (current_tab[0] == 2) then
			imgui.TextColored(imgui.ImVec4(0.88, 0.94, 1, 1), ux.languages_title);
			imgui.Separator();
			imgui.Spacing();
			language_selector(ux.display_lang, "##mylang", my_lang_idx, #lang_list - 1, function(v)
				my_lang = v;
			end);
			language_selector(ux.send_lang, "##outlang", out_lang_idx, #lang_list - 1, function(v)
				out_lang = v;
			end);
			language_selector(ux.server_lang, "##srvlang", srv_lang_idx, #lang_list, function(v)
				server_lang = v;
			end);
		elseif (current_tab[0] == 3) then
			imgui.TextColored(imgui.ImVec4(0.88, 0.94, 1, 1), ux.appearance_title);
			imgui.Separator();
			imgui.Spacing();
			do
				local r, g, b = ui_accent();
				local dl = imgui.GetWindowDrawList();
				local p = imgui.GetCursorScreenPos();
				dl:AddRectFilled(imgui.ImVec2(p.x, p.y + 2), imgui.ImVec2(p.x + 22, p.y + 20), imgui.U32(r, g, b, 1), 4);
				imgui.Dummy(imgui.ImVec2(26, 0));
				imgui.SameLine();
				imgui.TextColored(imgui.ImVec4(0.58, 0.67, 0.78, 1), "#27F595");
			end
		elseif (current_tab[0] == 4) then
			imgui.TextColored(imgui.ImVec4(0.88, 0.94, 1, 1), ux.faq_title);
			imgui.Separator();
			if imgui.CollapsingHeader(ux.faq_chat .. "##faq1") then
				imgui.TextWrapped(ux.faq_chat_text);
			end
			if imgui.CollapsingHeader(ux.faq_auto .. "##faq2") then
				imgui.TextWrapped(ux.faq_auto_text);
			end
			if imgui.CollapsingHeader(ux.faq_cache .. "##faq3") then
				imgui.TextWrapped(ux.faq_cache_text);
			end
			if imgui.CollapsingHeader(ux.faq_visual .. "##faq4") then
				imgui.TextWrapped(ux.faq_visual_text);
			end
			elseif (current_tab[0] == 6) then
				imgui.TextColored(imgui.ImVec4(0.88, 0.94, 1, 1), ux.hk_title);
				imgui.Separator();
				imgui.Spacing();
				hotkey_row(ux.hk_menu, "menu", ux);
				imgui.Spacing();
				hotkey_row(ux.hk_autotr, "auto", ux);
				imgui.Spacing();
				imgui.TextWrapped(ux.hk_hint);
			else
				imgui.TextColored(imgui.ImVec4(0.88, 0.94, 1, 1), ux.credits_title);
			imgui.Separator();
			imgui.Spacing();
			imgui.TextColored(imgui.ImVec4(r, g, b, 1), ux.created_by);
			imgui.Spacing();
			if imgui.Button(ux.discord, imgui.ImVec2(-1, 30)) then
				setClipboardText("@nautaro");
				chat("{27F595}[Translator] {FFFFFF}@nautaro");
			end
		end
		imgui.Separator();
		imgui.TextColored((config_dirty and imgui.ImVec4(1, 0.78, 0.3, 1)) or imgui.ImVec4(0.42, 0.9, 0.64, 1), (config_dirty and ux.pending) or ux.ready);
		if imgui.Button(ux.save, imgui.ImVec2(-1, 30)) then
			if save_translator_settings() then
				config_dirty = false;
				chat("{27F595}[Translator] {FFFFFF}" .. ux.ready);
			end
		end
		imgui.EndChild();
		imgui.PopStyleVar();
		imgui.End();
		imgui.PopStyleColor(12);
	end);
	local function to_utf8(str, lang)
		local is_ru = isRU(lang);
		local ce = isCE(lang);
		local conv = (is_ru and _CONV_CP1251_TO_U8) or (ce and _CONV_CP1250_TO_U8) or _CONV_CP1252_TO_U8;
		if conv then
			local res = conv:iconv(str);
			if (res and (res ~= "")) then
				return res;
			end
		end
		local saved = encoding.default;
		encoding.default = (is_ru and "CP1251") or (ce and "CP1250") or "CP1252";
		local ok, res = pcall(function()
			return u8(str);
		end);
		encoding.default = saved;
		return (ok and res and (res ~= "") and res) or str;
	end
	local function from_utf8(str, lang)
		local is_ru = isRU(lang);
		local ce = isCE(lang);
		if (lang == "RO") then
			return ro_fold_ascii(str);
		end
		if ce then
			str = normalize_ro(str);
		end
		local conv = (is_ru and _CONV_U8_TO_CP1251) or (ce and _CONV_U8_TO_CP1250) or _CONV_U8_TO_CP1252;
		if conv then
			local res = conv:iconv(str);
			if (res and (res ~= "")) then
				return res;
			end
		end
		local saved = encoding.default;
		encoding.default = (is_ru and "CP1251") or (ce and "CP1250") or "CP1252";
		local ok, res = pcall(function()
			return u8:decode(str);
		end);
		encoding.default = saved;
		return (ok and res and (res ~= "") and res) or str;
	end
	local function menu_decode(full, map)
		return unmask(from_utf8(fold_latin(full), my_lang), map);
	end
	local slang_dict = {["PT-BR"]={mlk="moleque",mds="meu deus",xitado="usando hack",xiter="hacker",pdp="com certeza",vlw="obrigado",flw="adeus",blz="beleza",tlgd="entendeu",fdp="filho da puta",slc="voce e louco",nmrl="falando serio",tmj="conta comigo",vdd="verdade",pq="por que",vc="voce",tbm="tambem",krl="caralho",pqp="puta que pariu",rlx="relaxa",sv="servidor",nd="nada",pfv="por favor",mto="muito",tmnc="tomar no cu",poha="porra",nb="novato",dms="demais",ain="ay",ss="sim",nn="nao",s="sim",n="nao",mano="hermano"},ES={q="que",xq="por que",pq="por que",tmb="tambien",xfa="por favor",grax="gracias",hdp="hijo de puta",ctm="concha tu madre",wbn="huevon",k="que",ptm="puta madre",np="no hay problema",klq="que pasa",weon="amigo",wn="amigo",s="si",n="no"},["EN-US"]={u="you",r="are",pls="please",plz="please",thx="thanks",ty="thank you",idk="i dont know",afk="away from keyboard",omg="oh my god",wtf="what the fuck",lmao="laughing my ass off",lol="laughing out loud",np="no problem",brb="be right back",gg="good game",btw="by the way"},RU={["спс"]="спасибо",["пж"]="пожалуйста",["хз"]="не знаю",["мг"]="метагейминг",["дб"]="драйвбай",["дм"]="дэтматч",["пздц"]="пиздец",["блять"]="блин",["ок"]="хорошо"},PL={zw="zaraz wracam",jj="juz jestem",thx="dzieki",nmzc="nie ma za co"},ID={yg="yang",dgn="dengan",klo="kalau",gw="saya",lu="kamu"},TR={hg="hoş geldin",hb="hoş bulduk",sa="selamın aleyküm",as="aleyküm selam",eyv="eyvallah",kb="kusura bakma",tm="tamam",tmm="tamam",nbr="ne haber",knk="kanka",amk="amına koyayım",aq="amına koyayım",sg="siktir git",olm="oğlum",lan="ulan",bb="bay bay",s="evet",n="hayır"},CS={},RO={}};
	if _CONV_U8_TO_CP1251 then
		local new_ru = {};
		for k, v in pairs(slang_dict['RU']) do
			local ck, cv = _CONV_U8_TO_CP1251:iconv(k), _CONV_U8_TO_CP1251:iconv(v);
			if (ck and (ck ~= "") and cv and (cv ~= "")) then
				new_ru[ck] = cv;
			end
		end
		slang_dict['RU'] = new_ru;
	end
	local function processSlang(str, lang)
		return str:gsub("(%a)%1%1%1+", "%1%1"):gsub("%a+", function(word)
			local w = word:lower();
			if ((lang ~= "AUTO") and slang_dict[lang] and slang_dict[lang][w]) then
				return ((word == word:upper()) and slang_dict[lang][w]:upper()) or slang_dict[lang][w];
			elseif (lang == "AUTO") then
				for _, dict in pairs(slang_dict) do
					if dict[w] then
						return ((word == word:upper()) and dict[w]:upper()) or dict[w];
					end
				end
			end
			return word;
		end);
	end
	local function isGibberish(text)
		if (not text or text:match("^%s*$")) then
			return true;
		end
		local _, cmds = text:gsub("/%w+", "");
		if (cmds > 2) then
			return true;
		end
		local pure = text:gsub("[%s%p]", ""):lower();
		return pure:match("^k+$") or pure:match("^x+d+$") or pure:match("^j+a+$");
	end
	local worker = effil.thread(function(utf8_text, source_lang, target_lang)
		local ffi = require("ffi");
		pcall(ffi.cdef, [[
        typedef void* HINTERNET; typedef unsigned long DWORD; typedef int BOOL;
        HINTERNET InternetOpenA(const char* a, DWORD b, const char* c, const char* d, DWORD e);
        HINTERNET InternetOpenUrlA(HINTERNET h, const char* url, const char* hdr, DWORD hl, DWORD flags, DWORD* ctx);
        BOOL InternetReadFile(HINTERNET f, void* buf, DWORD n, DWORD* read);
        BOOL InternetCloseHandle(HINTERNET h);
        BOOL InternetSetOptionA(HINTERNET h, DWORD o, void* b, DWORD l);
    ]]);
		local wi = ffi.load("wininet");
		local ue = utf8_text:gsub("([^%w%-%.%_%~ ])", function(c)
			return string.format("%%%02X", string.byte(c));
		end):gsub(" ", "+");
		local url = "https://translate.googleapis.com/translate_a/single?client=gtx&sl=" .. source_lang .. "&tl=" .. target_lang .. "&dt=t&q=" .. ue;
		local req_headers = "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64)\r\nConnection: close\r\n";
		local ctx = ffi.new("DWORD[1]", 0);
		local hNet = wi.InternetOpenA("Mozilla/5.0", 0, nil, nil, 0);
		if not hNet then
			return false, "";
		end
		for _, opt in ipairs({{2, 5000}, {5, 5000}, {6, 9000}}) do
			wi.InternetSetOptionA(hNet, opt[1], ffi.new("DWORD[1]", opt[2]), 4);
		end
		local hUrl = wi.InternetOpenUrlA(hNet, url, req_headers, #req_headers, 2214592512, ctx);
		if not hUrl then
			wi.InternetCloseHandle(hNet);
			return false, "";
		end
		local buf = ffi.new("char[8192]");
		local nRead = ffi.new("DWORD[1]");
		local read_ok, body = pcall(function()
			local chunks = {};
			local totalRead = 0;
			while totalRead < 32768 do
				if ((wi.InternetReadFile(hUrl, buf, 8192, nRead) == 0) or (nRead[0] == 0)) then
					break;
				end
				table.insert(chunks, ffi.string(buf, nRead[0]));
				totalRead = totalRead + nRead[0];
			end
			return table.concat(chunks);
		end);
		wi.InternetCloseHandle(hUrl);
		wi.InternetCloseHandle(hNet);
		if not read_ok then
			return false, "";
		end
		return true, body;
	end);
	local function safe_decode_google_json(raw_body)
		if (type(raw_body) ~= "string") then
			return false, nil;
		end
		-- Ignore an UTF-8 BOM and leading whitespace before the JSON payload.
		raw_body = raw_body:gsub("^\239\187\191", ""):gsub("^%s+", "");
		-- The Google Translate endpoint used here returns a JSON array.
		-- Do not send HTML/plain-text error pages to CJSON.
		if (raw_body == "" or raw_body:sub(1, 1) ~= "[") then
			return false, nil;
		end
		local ok, parsed = pcall(decodeJson, raw_body);
		if (not ok) then
			return false, nil;
		end
		return true, parsed;
	end
	local pending_out = nil;
	local dialog_replay, bubble_replay, label_replay, chat_replay, chat_rpc_replay, outgoing_replay = false, false, false, false, false, false;
	local td_pending, td_waiting, td_pending_by_key, td_versions = {}, {}, {}, {};
	local td_active_limit, td_wait_limit = 8, 128;
	local td_registry, td_registry_order = {}, {};
	local label_registry, label_registry_order = {}, {};
	local function td_registry_store(id, is_player, text)
		local key = (is_player and ("p" .. id)) or ("g" .. id);
		local entry = td_registry[key];
		if entry then
			entry.text = text;
			return;
		end
		td_registry[key] = {id=id, text=text, is_player=is_player};
		table.insert(td_registry_order, key);
		if (#td_registry_order > 256) then
			td_registry[table.remove(td_registry_order, 1)] = nil;
		end
	end
	local function label_registry_store(id, data, text)
		local entry = label_registry[id];
		if entry then
			entry.text = text;
			entry.data = data;
			return;
		end
		label_registry[id] = {id=id, data=data, text=text};
		table.insert(label_registry_order, id);
		if (#label_registry_order > 384) then
			label_registry[table.remove(label_registry_order, 1)] = nil;
		end
	end
	local menu_cache_dir = getWorkingDirectory() .. "\\config\\TranslatorUltimate";
	if not doesDirectoryExist(menu_cache_dir) then
		createDirectory(menu_cache_dir);
	end
	local menu_cache_path = menu_cache_dir .. "\\menu_translations_v2.cache";
	local menu_cache_data, menu_cache_order, menu_cache_dirty = {}, {}, false;
	local menu_cache_journal, menu_cache_appended = {}, 0;
	local menu_cache_touch = {};
	local menu_cache_limit = 4000;
	local function hex_encode(value)
		return (value:gsub(".", function(char)
			return string.format("%02X", string.byte(char));
		end));
	end
	local function hex_decode(value)
		return (value:gsub("%x%x", function(hex)
			return string.char(tonumber(hex, 16));
		end));
	end
	local function load_menu_cache()
		local file = io.open(menu_cache_path, "r");
		if not file then
			return;
		end
		for line in file:lines() do
			local key, value = line:match("^(%x+)|(%x+)$");
			if (key and value) then
				key, value = hex_decode(key), hex_decode(value);
				if not menu_cache_data[key] then
					table.insert(menu_cache_order, key);
				end
				menu_cache_data[key] = value;
			end
		end
		file:close();
		while #menu_cache_order > menu_cache_limit do
			menu_cache_data[table.remove(menu_cache_order, 1)] = nil;
		end
	end
	local function flush_menu_cache()
		if not menu_cache_dirty then
			return;
		end
		local compact = (menu_cache_appended >= menu_cache_limit);
		local file = io.open(menu_cache_path, compact and "w" or "a");
		if not file then
			return;
		end
		local written = 0;
		if compact then
			for _, key in ipairs(menu_cache_order) do
				local value = menu_cache_data[key];
				if value then
					file:write(hex_encode(key) .. "|" .. hex_encode(value) .. "\n");
					written = written + 1;
				end
			end
			menu_cache_appended = 0;
		else
			for key in pairs(menu_cache_journal) do
				local value = menu_cache_data[key];
				if value then
					file:write(hex_encode(key) .. "|" .. hex_encode(value) .. "\n");
					written = written + 1;
				end
			end
			menu_cache_appended = menu_cache_appended + written;
		end
		file:close();
		menu_cache_journal = {};
		menu_cache_dirty = false;
	end
	local function menu_cache_key(scope, text, source, target)
		return "v2\1" .. (scope or "menu") .. "\1" .. (target or my_lang) .. "\1" .. (source or server_lang) .. "\1" .. text;
	end
	local function menu_cache_get(key)
		local val = menu_cache_data[key];
		if val then
			menu_cache_touch[key] = os.clock();
		end
		return val;
	end
	local function menu_cache_put(key, value)
		if not menu_cache_data[key] then
			table.insert(menu_cache_order, key);
			if (#menu_cache_order > menu_cache_limit) then
				local oldest_key, oldest_time = nil, nil;
				for _, cand in ipairs(menu_cache_order) do
					local t = menu_cache_touch[cand] or 0;
					if (oldest_time == nil) or (t < oldest_time) then
						oldest_key, oldest_time = cand, t;
					end
				end
				if oldest_key then
					for i, cand in ipairs(menu_cache_order) do
						if (cand == oldest_key) then
							table.remove(menu_cache_order, i);
							break;
						end
					end
					menu_cache_data[oldest_key] = nil;
					menu_cache_touch[oldest_key] = nil;
				end
			end
		end
		menu_cache_data[key] = value;
		menu_cache_touch[key] = os.clock();
		menu_cache_journal[key] = true;
		menu_cache_dirty = true;
	end
	load_menu_cache();
	local function doTranslate(text)
		text = text:gsub('^%s*["\'](.+)["\']%s*$', "%1"):gsub("^%s+", ""):gsub("%s+$", "");
		local p = text:match("^([!@#$*]+)");
		local prefix = p or "";
		if p then
			text = text:sub(#p + 1):gsub("^%s+", "");
		end
		if (only_clan and not prefix:find("!")) then
			prefix = "!" .. prefix;
		end
		if (text == "") then
			return;
		end
		local src_lang = (looks_cyrillic(text) and "RU") or my_lang;
		local utf8_msg = to_utf8(text, src_lang);
		local cache_key = out_lang .. "|" .. utf8_msg;
		if cache[cache_key] then
			return sampSendChat(prefix .. cache[cache_key]);
		end
		if pending_out then
			return chat(L[my_lang].wait);
		end
		local now = os.clock();
		if ((now - last_use) < 1) then
			return;
		end
		last_use = now;
		chat(L[my_lang].translating);
		local tl_fmt = ((out_lang == "AUTO") and "en") or formatLang(out_lang);
		pending_out = {thread=worker(utf8_msg, formatLang(src_lang), tl_fmt),original=text,prefix=prefix,key=cache_key,target_lang=out_lang,started=os.clock()};
	end
	local function td_should(text)
		if not text then
			return false;
		end
		local t = text:gsub("~.-~", " "):gsub("^%s+", ""):gsub("%s+$", "");
		if (#t < 3) then
			return false;
		end
		if t:find("%$%d") then
			return false;
		end
		local _, letters = t:gsub("%a", "");
		if (letters < 3) then
			return false;
		end
		local _, visible = t:gsub("%S", "");
		if ((visible == 0) or ((letters / visible) < 0.6)) then
			return false;
		end
		return true;
	end
	local function is_game_title(text)
		local clean = text:gsub("{%x%x%x%x%x%x}", ""):gsub("~[%a%d]~", "");
		local rest = clean;
		for _, phrase in ipairs(PROTECT_PHRASES) do
			rest = rest:gsub(escape_lua_pattern(phrase), "");
		end
		rest = rest:gsub("[%s%p%d_]", "");
		if (#rest < 3) then
			return true;
		end
		if ((#clean < 42) and clean:match("^%s*[A-Z][A-Za-z0-9]*[%s%-]+[A-Z][A-Za-z0-9]*%s*$")) then
			return true;
		end
		return false;
	end
	local function is_ui_noise(text)
		local clean = text:gsub("{%x%x%x%x%x%x}", ""):gsub("~[%a%d]~", "");
		if (clean:match("^%s*%[AFK%]") or clean:match("^%s*%b[]%s*%b[]%s*$")) then
			return true;
		end
		local residual = clean:gsub("%b[]", ""):gsub("[%s%p%d_]", "");
		return #residual < 3;
	end
	local function translation_should(text)
		if not text then
			return false;
		end
		local clean = text:gsub("{%x%x%x%x%x%x}", ""):gsub("~[%a%d]~", "");
		local _, letters = clean:gsub("[%a\192-\255]", "");
		return (letters >= 2) and not is_ui_noise(text) and not is_game_title(text);
	end
	local function translation_enabled_for(kind)
		if ((kind == "chat_in") or (kind == "chat_in_message") or (kind == "chat_rpc") or (kind == "chat_rpc_message") or (kind == "chat_out")) then
			return chat_tr_enabled;
		end
		if ((kind == "dialog") or (kind == "textdraw")) then
			return menu_tr_enabled;
		end
		if (kind == "bubble") then
			return head_tr_enabled;
		end
		if (kind == "3d") then
			return text3d_tr_enabled;
		end
		return false;
	end
	local function pending_count(kind)
		local count = 0;
		for _, item in ipairs(td_pending) do
			if (item.kind == kind) then
				count = count + 1;
			end
		end
		for _, item in ipairs(td_waiting) do
			if (item.kind == kind) then
				count = count + 1;
			end
		end
		return count;
	end
	local function can_queue(kind)
		local total = #td_pending + #td_waiting;
		if (total >= td_wait_limit) then
			return false;
		end
		if ((kind == "chat_in") or (kind == "chat_in_message") or (kind == "chat_rpc") or (kind == "chat_rpc_message") or (kind == "chat_out")) then
			return (pending_count("chat_in") + pending_count("chat_in_message") + pending_count("chat_rpc") + pending_count("chat_rpc_message") + pending_count("chat_out")) < 64;
		end
		if ((kind == "dialog") or (kind == "3d") or (kind == "bubble")) then
			return (pending_count("dialog") + pending_count("3d") + pending_count("bubble")) < 32;
		end
		if (kind == "textdraw") then
			return pending_count("textdraw") < 16;
		end
		return true;
	end
	local function translation_priority(kind)
		if ((kind == "chat_in") or (kind == "chat_in_message") or (kind == "chat_rpc") or (kind == "chat_rpc_message") or (kind == "chat_out")) then
			return 1;
		end
		if (kind == "dialog") then
			return 2;
		end
		if ((kind == "3d") or (kind == "bubble")) then
			return 3;
		end
		return 4;
	end
	local function start_pending_translations()
		while (#td_pending < td_active_limit) and (#td_waiting > 0) do
			local best, best_priority = 1, translation_priority(td_waiting[1].kind);
			for i = 2, #td_waiting do
				local p = translation_priority(td_waiting[i].kind);
				if (p < best_priority) then
					best, best_priority = i, p;
				end
			end
			local item = table.remove(td_waiting, best);
			item.thread = worker(item.payload, item.google_source, item.google_target);
			item.started = os.clock();
			table.insert(td_pending, item);
		end
	end
	local function make_delivery(kind, id, extra, target_lang)
		extra = extra or {};
		if ((kind == "textdraw") or (kind == "3d") or (kind == "dialog")) then
			local version_key = kind .. ":" .. tostring(id);
			td_versions[version_key] = (td_versions[version_key] or 0) + 1;
			extra.version_key, extra.version = version_key, td_versions[version_key];
		end
		return {kind=kind,id=id,extra=extra,target_lang=target_lang};
	end
	local function queue_translation(kind, id, text, extra, enabled, source_lang, target_lang, scope, auto_source)
		source_lang = source_lang or (looks_cyrillic(text) and "RU") or server_lang;
		target_lang = target_lang or my_lang;
		local delivery = make_delivery(kind, id, extra, target_lang);
		if (not enabled or not translation_should(text)) then
			return nil, false;
		end
		local key = menu_cache_key(scope, text, source_lang, target_lang);
		local cached = menu_cache_get(key);
		if cached then
			return cached, false;
		end
		local existing = td_pending_by_key[key];
		if existing then
			table.insert(existing.deliveries, delivery);
			return nil, true;
		end
		if not can_queue(kind) then
			return nil, false;
		end
		local masked, map = mask_protect(text);
		local slanged = processSlang(masked, source_lang);
		if not slanged:find("[%a\192-\255]") then
			menu_cache_put(key, text);
			return text, false;
		end
		local google_source = (((auto_source and not looks_cyrillic(text)) or (source_lang == "AUTO")) and "auto") or formatLang(source_lang);
		local google_target = ((target_lang == "AUTO") and "en") or formatLang(target_lang);
		local item = {kind=kind,id=id,key=key,cache_key=key,map=map,target_lang=target_lang,deliveries={delivery},payload=to_utf8(slanged, source_lang),google_source=google_source,google_target=google_target};
		td_pending_by_key[key] = item;
		table.insert(td_waiting, item);
		return nil, true;
	end
	local function queue_menu_translation(kind, id, text, extra)
		local source = (looks_cyrillic(text) and "RU") or server_lang;
		return queue_translation(kind, id, text, extra, translation_enabled_for(kind), source, my_lang, "menu", true);
	end
		local function print_player_message_translation(text, prefix, playerId)
			local nick = "";
			if (playerId and (playerId >= 0) and (playerId < 1004)) then
				local ok, name = pcall(sampGetPlayerNickname, playerId);
				if (ok and name and (name ~= "") and sampIsPlayerConnected(playerId)) then
					nick = name .. ": ";
				end
			end
		local line = ((prefix or "") .. text):gsub("{%x%x%x%x%x%x}", "");
		sampAddChatMessage("{27F595}" .. nick .. "[Auto-TR] {FFFFFF}" .. line, -1);
		end
	local function is_server_player_chat(text)
		return text:match("^.-%s*%(%d+%)[^:]*:%s+.+$") ~= nil;
	end
	local function td_handle(id, is_player, data)
		td_registry_store(id, is_player, data.text);
		if not translation_enabled_for("textdraw") then
			return false;
		end
		local cached = queue_menu_translation("textdraw", id, data.text, {is_player=is_player});
		if cached then
			data.text = cached;
			return true;
		end
		return false;
	end
	if ok_sampev then
		sampev.onServerMessage = function(color, text)
			if (chat_replay or not chat_tr_enabled) then
				return;
			end
			local clean_text = text:gsub("{%x%x%x%x%x%x}", "");
			if clean_text:find("/ZVH") then
				return;
			end
			detect_server_language(clean_text);
			if (only_clan and not clean_text:find("%(!%)")) then
				return;
			end
			local prefix, message = text:match("^(.-:%s*)(.+)$");
			if not message then
				prefix, message = "", text;
			end
			local source = (looks_cyrillic(message) and "RU") or server_lang;
			if ((chat_translation_mode == "messages") and is_server_player_chat(clean_text)) then
				local cached = queue_translation("chat_in_message", 0, message, {prefix=prefix,mode="messages"}, chat_tr_enabled, source, my_lang, "chat_in_message", true);
				if cached then
					print_player_message_translation(cached, prefix);
				end
				return;
			end
			local cached, queued = queue_translation("chat_in", 0, message, {color=color,prefix=prefix}, chat_tr_enabled, source, my_lang, "chat_in", true);
			if cached then
				replay_server_message({color=color}, prefix .. cached);
				return false;
			end
			if queued then
				return false;
			end
		end;
		sampev.onSendChat = function(message)
			if (outgoing_replay or not chat_tr_enabled or not auto_out_enabled or message:find("^/")) then
				return;
			end
			local source = (looks_cyrillic(message) and "RU") or my_lang;
			local cached, queued = queue_translation("chat_out", 0, message, {}, chat_tr_enabled, source, out_lang, "chat_out", false);
			if cached then
				outgoing_replay = true;
				sampSendChat(cached);
				outgoing_replay = false;
				return false;
			end
			if queued then
				chat(L[my_lang].translating);
				return false;
			end
		end;
		sampev.onChatMessage = function(playerId, text)
				if (chat_rpc_replay or not chat_tr_enabled) then
					return;
				end
				detect_server_language(text);
				local source = (looks_cyrillic(text) and "RU") or server_lang;
				if (chat_translation_mode == "messages") then
					local cached, queued = queue_translation("chat_rpc_message", playerId, text, {mode="messages", playerId=playerId}, chat_tr_enabled, source, my_lang, "chat_rpc_message", true);
					if cached then
						print_player_message_translation(cached, nil, playerId);
					end
					return;
				end
				local cached, queued = queue_translation("chat_rpc", playerId, text, {playerId=playerId}, chat_tr_enabled, source, my_lang, "chat_rpc", true);
				if cached then
					replay_chat_rpc({playerId=playerId}, cached);
					return false;
				end
				if queued then
					return false;
				end
			end;
		local function dialog_fields(translated)
			local p1 = translated:find("\n", 1, true);
			local p2 = p1 and translated:find("\n", p1 + 1, true);
			local p3 = p2 and translated:find("\n", p2 + 1, true);
			if not (p1 and p2 and p3) then
				return nil;
			end
			return translated:sub(1, p1 - 1), translated:sub(p1 + 1, p2 - 1), translated:sub(p2 + 1, p3 - 1), translated:sub(p3 + 1);
		end
		function replay_dialog(data, translated)
			local title, button1, button2, text = dialog_fields(translated);
			if not title then
				return;
			end
			dialog_replay = true;
			local bs = raknetNewBitStream();
			raknetBitStreamWriteInt16(bs, data.dialogId);
			raknetBitStreamWriteInt8(bs, data.style);
			raknetBitStreamWriteInt8(bs, title:len());
			raknetBitStreamWriteString(bs, title);
			raknetBitStreamWriteInt8(bs, button1:len());
			raknetBitStreamWriteString(bs, button1);
			raknetBitStreamWriteInt8(bs, button2:len());
			raknetBitStreamWriteString(bs, button2);
			raknetBitStreamEncodeString(bs, text);
			raknetEmulRpcReceiveBitStream(61, bs);
			raknetDeleteBitStream(bs);
			sampSetDialogClientside(false);
			dialog_replay = false;
		end
		function replay_3d_text(data, text)
			label_replay = true;
			local bs = raknetNewBitStream();
			raknetBitStreamWriteInt16(bs, data.id);
			raknetBitStreamWriteInt32(bs, data.color);
			raknetBitStreamWriteFloat(bs, data.position.x);
			raknetBitStreamWriteFloat(bs, data.position.y);
			raknetBitStreamWriteFloat(bs, data.position.z);
			raknetBitStreamWriteFloat(bs, data.distance);
			raknetBitStreamWriteInt8(bs, (data.testLOS and 1) or 0);
			raknetBitStreamWriteInt16(bs, data.attachedPlayerId);
			raknetBitStreamWriteInt16(bs, data.attachedVehicleId);
			raknetBitStreamEncodeString(bs, text);
			raknetEmulRpcReceiveBitStream(36, bs);
			raknetDeleteBitStream(bs);
			label_replay = false;
		end
		function replay_chat_rpc(data, text)
			chat_rpc_replay = true;
			local bs = raknetNewBitStream();
			local message = text:sub(1, 255);
			raknetBitStreamWriteInt16(bs, data.playerId);
			raknetBitStreamWriteInt8(bs, message:len());
			raknetBitStreamWriteString(bs, message);
			raknetEmulRpcReceiveBitStream(101, bs);
			raknetDeleteBitStream(bs);
			chat_rpc_replay = false;
		end
		function replay_server_message(data, text)
			chat_replay = true;
			local bs = raknetNewBitStream();
			raknetBitStreamWriteInt32(bs, data.color);
			raknetBitStreamWriteInt32(bs, text:len());
			raknetBitStreamWriteString(bs, text);
			raknetEmulRpcReceiveBitStream(93, bs);
			raknetDeleteBitStream(bs);
			chat_replay = false;
		end
		local function delivery_is_current(delivery)
			local extra = delivery and delivery.extra;
			return not (extra and extra.version_key) or (td_versions[extra.version_key] == extra.version);
		end
		function deliver_translation(delivery, res)
			if (not delivery_is_current(delivery) or not translation_enabled_for(delivery.kind)) then
				return;
			end
			local kind, id, extra = delivery.kind, delivery.id, delivery.extra or {};
			if (((kind == "chat_out") and (delivery.target_lang ~= out_lang)) or ((kind ~= "chat_out") and (delivery.target_lang ~= my_lang))) then
				return;
			end
			if (kind == "chat_in") then
				replay_server_message(extra, (extra.prefix or "") .. res);
			elseif (kind == "chat_in_message") then
				if (extra.mode == chat_translation_mode) then
					print_player_message_translation(res, extra.prefix);
				end
			elseif (kind == "chat_rpc") then
				replay_chat_rpc(extra, res);
			elseif (kind == "chat_rpc_message") then
				if (extra.mode == chat_translation_mode) then
					print_player_message_translation(res, nil, extra.playerId);
				end
			elseif (kind == "chat_out") then
				outgoing_replay = true;
				sampSendChat(res);
				outgoing_replay = false;
			elseif (kind == "dialog") then
				replay_dialog(extra, res);
			elseif (kind == "3d") then
				replay_3d_text(extra, res);
			elseif (kind == "bubble") then
				if (os.clock() < (extra.expires or 0)) then
					bubble_replay = true;
					local bs = raknetNewBitStream();
					raknetBitStreamWriteInt16(bs, extra.playerId);
					raknetBitStreamWriteInt32(bs, extra.color);
					raknetBitStreamWriteFloat(bs, extra.distance);
					raknetBitStreamWriteInt32(bs, math.max(0, math.floor((extra.expires - os.clock()) * 1000)));
					local bubble_text = res:sub(1, 255);
					raknetBitStreamWriteInt8(bs, bubble_text:len());
					raknetBitStreamWriteString(bs, bubble_text);
					raknetEmulRpcReceiveBitStream(59, bs);
					raknetDeleteBitStream(bs);
					bubble_replay = false;
				end
			elseif (kind == "textdraw") then
				if (not extra.is_player and sampTextdrawSetString) then
					sampTextdrawSetString(id, res);
				end
			end
		end
		sampev.onShowDialog = function(dialogId, style, title, button1, button2, text)
			if (dialog_replay or not translation_enabled_for("dialog")) then
				return;
			end
			local d_title, d_button1, d_button2, d_text = title or "", button1 or "", button2 or "", text or "";
			local original = d_title .. "\n" .. d_button1 .. "\n" .. d_button2 .. "\n" .. d_text;
			local cached, queued = queue_menu_translation("dialog", dialogId, original, {dialogId=dialogId,style=style});
			if cached then
				local tr_title, tr_button1, tr_button2, tr_text = dialog_fields(cached);
				if tr_title then
					return {dialogId,style,tr_title,tr_button1,tr_button2,tr_text};
				end
			end
			if queued then
				return false;
			end
		end;
		sampev.onShowTextDraw = function(id, data)
			if td_handle(id, false, data) then
				return {id,data};
			end
		end;
		sampev.onTextDrawSetString = function(id, text)
			td_registry_store(id, false, text);
			if not translation_enabled_for("textdraw") then
				return;
			end
			local cached, queued = queue_menu_translation("textdraw", id, text, {is_player=false});
			if cached then
				return {id,cached};
			end
			if queued then
				return false;
			end
		end;
		sampev.onShowPlayerTextDraw = function(id, data)
			if td_handle(id, true, data) then
				return {id,data};
			end
		end;
		sampev.onCreate3DText = function(id, color, position, distance, testLOS, attachedPlayerId, attachedVehicleId, text)
			if label_replay then
				return;
			end
			local data = {id=id,color=color,position=position,distance=distance,testLOS=testLOS,attachedPlayerId=attachedPlayerId,attachedVehicleId=attachedVehicleId};
			label_registry_store(id, data, text);
			local cached, queued = queue_menu_translation("3d", id, text, data);
			if cached then
				replay_3d_text(data, cached);
				return false;
			end
			if queued then
				return false;
			end
		end;
		sampev.onPlayerChatBubble = function(playerId, color, distance, duration, message)
			if bubble_replay then
				return;
			end
			local cached, queued = queue_menu_translation("bubble", playerId, message, {playerId=playerId,color=color,distance=distance,duration=duration,expires=(os.clock() + (duration / 1000))});
			if cached then
				return {playerId,color,distance,duration,cached};
			end
			if queued then
				return false;
			end
		end;
	end
	refresh_menu_translations = function()
		if menu_tr_enabled then
			for _, entry in pairs(td_registry) do
				if (not entry.is_player) then
				local cached = queue_menu_translation("textdraw", entry.id, entry.text, {is_player=false});
				if (cached and sampTextdrawSetString) then
					pcall(sampTextdrawSetString, entry.id, cached);
				end
				end
			end
		else
			for _, entry in pairs(td_registry) do
				if ((not entry.is_player) and sampTextdrawSetString) then
					pcall(sampTextdrawSetString, entry.id, entry.text);
				end
			end
		end
		if replay_3d_text then
			if text3d_tr_enabled then
				for _, entry in pairs(label_registry) do
					local src = entry.data;
					local extra = {id=src.id,color=src.color,position=src.position,distance=src.distance,testLOS=src.testLOS,attachedPlayerId=src.attachedPlayerId,attachedVehicleId=src.attachedVehicleId};
					local cached = queue_menu_translation("3d", entry.id, entry.text, extra);
					if cached and not pcall(replay_3d_text, extra, cached) then
						label_replay = false;
					end
				end
			else
				for _, entry in pairs(label_registry) do
					if not pcall(replay_3d_text, entry.data, entry.text) then
						label_replay = false;
					end
				end
			end
		end
	end
	sampRegisterChatCommand("tr", doTranslate);
	local function toggle_autotr()
		chat_tr_enabled = not chat_tr_enabled;
		autotr_enabled = chat_tr_enabled;
		chat_auto_cb[0] = chat_tr_enabled and (chat_translation_mode == "automatic");
		chat_messages_cb[0] = chat_tr_enabled and (chat_translation_mode == "messages");
		config_dirty = true;
		save_translator_settings();
		config_dirty = false;
		chat((chat_tr_enabled and L[my_lang].autotr_on) or L[my_lang].autotr_off);
	end
	sampRegisterChatCommand("autotr", toggle_autotr);
	sampRegisterChatCommand("trkey", function(arg)
		local which, key = arg:lower():match("^(%a+)%s+(%w+)$");
		if (not key or ((which ~= "menu") and (which ~= "auto"))) then
			chat("{27F595}[TR] {FFFFFF}Usage: /trkey <menu|auto> <F1-F12|A-Z|0-9|off>");
			return;
		end
		local vk = -1;
		if (key == "off") then
			vk = 0;
		elseif key:match("^f[1-9]$") or key:match("^f1[0-2]$") then
			vk = 111 + tonumber(key:sub(2));
		elseif (#key == 1) then
			local b = string.byte(key:upper());
			if ((b >= 48) and (((b <= 57)) or ((b >= 65) and (b <= 90)))) then
				vk = b;
			end
		end
		if (vk < 0) then
			chat("{27F595}[TR] {FFFFFF}Invalid key");
			return;
		end
		if (which == "menu") then
			hotkey_menu_vk, mainCfg.config.hotkey_menu = vk, vk;
		else
			hotkey_auto_vk, mainCfg.config.hotkey_auto = vk, vk;
		end
		inicfg.save(mainCfg, iniFileName);
		chat("{27F595}[TR] {FFFFFF}Hotkey " .. which .. ": " .. ((vk > 0) and key:upper() or "off"));
	end);
	sampRegisterChatCommand("trmenu", function()
		menu_active[0] = not menu_active[0];
	end);
	sampRegisterChatCommand("trlocale", function()
		chat("{FFCC66}[TR] {FFFFFF}Russian locale is embedded in gta_sa.exe; restore the backup with the game closed to revert it.");
	end);
	function onScriptTerminate(script, quitGame)
		if (script == thisScript()) then
			pcall(flush_menu_cache);
			pcall(inicfg.save, mainCfg, iniFileName);
		end
	end
	local function apply_update(luac_bytes)
		local dir = getWorkingDirectory();
		local tmp_path = dir .. "\\translator.luac.new";
		local ok, f = pcall(io.open, tmp_path, "wb");
		if (ok and f) then
			f:write(luac_bytes);
			f:close();
			os.remove(dir .. "\\translator.luac.old");
			os.rename(dir .. "\\translator.luac", dir .. "\\translator.luac.old");
			if os.rename(tmp_path, dir .. "\\translator.luac") then
				chat("{27F595}[TR] {FFFFFF}Actualización instalada. Recargando script...");
				pcall(function() thisScript():reload(); end);
			else
				os.rename(dir .. "\\translator.luac.old", dir .. "\\translator.luac");
			end
		end
	end
	local function start_update_check()
		if ((not ok_updater) or (not auto_update_enabled) or (auto_update_url == "") or upd_check_started > 0) then
			return;
		end
		upd_check_started = os.clock();
		upd_check_thread = updater.fetch(auto_update_url);
	end
	function main()
		local last_menu_cache_flush = os.clock();
		local last_server_check = 0;
		while not isSampAvailable() do
			wait(100);
		end
		chat(L[my_lang].welcome);
		apply_server_profile();
		start_update_check();
		if not _CONV_U8_TO_CP1250 then
			sampAddChatMessage("{FF8888}[TR] iconv CP1250 no disponible (revisa el build de iconv)", -1);
		end
		last_main_tick = os.clock();
		while true do
			wait(0);
			last_main_tick = os.clock();
			if ((hotkey_menu_vk or 0) > 0) and wasKeyPressed(hotkey_menu_vk) then
				if not ((sampIsChatInputActive and sampIsChatInputActive()) or (sampIsDialogActive and sampIsDialogActive())) then
					menu_active[0] = not menu_active[0];
				end
			end
			if ((hotkey_auto_vk or 0) > 0) and wasKeyPressed(hotkey_auto_vk) then
				if not ((sampIsChatInputActive and sampIsChatInputActive()) or (sampIsDialogActive and sampIsDialogActive())) then
					toggle_autotr();
				end
			end
			if ((os.clock() - last_server_check) >= 2) then
				last_server_check = os.clock();
				apply_server_profile();
			end
			if (upd_check_thread and (upd_check_thread:status() == "completed")) then
				local ok_res, body = upd_check_thread:get();
				upd_check_thread = nil;
				if (ok_res and body and (body ~= "")) then
					local ver, url = updater.parse(body);
					if (ver and updater.newer(ver, SCRIPT_VERSION)) then
						upd_new_version = ver;
						local target = ((url and (url ~= "")) and url) or auto_update_url:gsub("version%.json$", "translator.lua");
						upd_dl_thread = updater.fetch(target);
						upd_dl_started = os.clock();
					end
				end
			end
			if (upd_dl_thread and (upd_dl_thread:status() == "completed")) then
				local ok_dl, dl_body = upd_dl_thread:get();
				upd_dl_thread = nil;
				if (ok_dl and dl_body and (#dl_body > 1024) and dl_body:find("script_name", 1, true)) then
					local ok_dump, chunk = pcall(loadstring, dl_body);
					if (ok_dump and chunk) then
						local ok_bytes, luac_bytes = pcall(string.dump, chunk);
						if (ok_bytes and luac_bytes) then
							pcall(apply_update, luac_bytes);
						end
					end
				end
			end
			if (upd_check_thread and ((os.clock() - upd_check_started) > 15)) then
				pcall(upd_check_thread.cancel, upd_check_thread);
				upd_check_thread = nil;
			end
			if (upd_dl_thread and ((os.clock() - upd_dl_started) > 30)) then
				pcall(upd_dl_thread.cancel, upd_dl_thread);
				upd_dl_thread = nil;
			end
			if ui_capture_target then
				if wasKeyPressed(27) then
					ui_capture_target = nil;
				elseif not ((sampIsChatInputActive and sampIsChatInputActive()) or (sampIsDialogActive and sampIsDialogActive())) then
					for vk = 8, 255 do
						if ((vk ~= 16) and (vk ~= 17) and (vk ~= 18) and wasKeyPressed(vk)) then
							set_vk(ui_capture_target, vk);
							ui_capture_target = nil;
							break;
						end
					end
				end
			end
			start_pending_translations();
			if (menu_cache_dirty and ((os.clock() - last_menu_cache_flush) >= 5)) then
				flush_menu_cache();
				last_menu_cache_flush = os.clock();
			end
			if (menu_active[0] and (isGamePaused() or wasKeyPressed(27))) then
				menu_active[0] = false;
			end
			if pending_out then
				local status = pending_out.thread:status();
				if (status == "completed") then
					local ok, raw_body = pending_out.thread:get();
					if (ok and raw_body and (raw_body ~= "")) then
						local p_ok, parsed = safe_decode_google_json(raw_body);
						if (p_ok and (type(parsed) == "table") and (type(parsed[1]) == "table")) then
							local full_translation = "";
							for _, block in ipairs(parsed[1]) do
								if ((type(block) == "table") and (type(block[1]) == "string")) then
									full_translation = full_translation .. block[1];
								end
							end
							if (full_translation ~= "") then
								local result_str = full_translation:gsub("\n", " ");
								result_str = from_utf8(result_str, pending_out.target_lang);
								mem_cache_put(pending_out.key, result_str);
								outgoing_replay = true;
								sampSendChat(pending_out.prefix .. result_str);
								outgoing_replay = false;
							end
						end
					end
						pending_out = nil;
					elseif (status == "failed") then
						pending_out = nil;
					elseif ((os.clock() - (pending_out.started or os.clock())) > 15) then
						pcall(function()
							pending_out.thread:cancel();
						end);
						pending_out = nil;
					end
				end
			for i = #td_pending, 1, -1 do
				local item, status = td_pending[i], td_pending[i].thread:status();
				if (status == "completed") then
					local ok, raw_body = item.thread:get();
					if (ok and raw_body and (raw_body ~= "")) then
						local p_ok, parsed = safe_decode_google_json(raw_body);
						if (p_ok and (type(parsed) == "table") and (type(parsed[1]) == "table")) then
							local full = "";
							for _, block in ipairs(parsed[1]) do
								if ((type(block) == "table") and (type(block[1]) == "string")) then
									full = full .. block[1];
								end
							end
							if (full ~= "") then
								local res = unmask(from_utf8(fold_latin(full), item.target_lang or my_lang), item.map);
								if item.cache_key then
									menu_cache_put(item.cache_key, res);
								end
								for _, delivery in ipairs(item.deliveries or {}) do
									deliver_translation(delivery, res);
								end
							end
						end
					end
					td_pending_by_key[item.cache_key] = nil;
					table.remove(td_pending, i);
				elseif (status == "failed") then
					td_pending_by_key[item.cache_key] = nil;
					table.remove(td_pending, i);
				elseif ((os.clock() - (item.started or os.clock())) > 15) then
					pcall(function()
						item.thread:cancel();
					end);
					td_pending_by_key[item.cache_key] = nil;
					table.remove(td_pending, i);
				end
			end
		end
	end
end
