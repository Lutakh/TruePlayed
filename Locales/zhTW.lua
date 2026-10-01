-- Locales/zhTW.lua - Traditional Chinese strings of TruePlayed (complete translation).
-- A copy of frFR.lua (see the recipe at the top of enUS.lua): it builds its own table and
-- registers it as ns.LOCALES[CODE]; Core applies it into ns.L when the "language" setting
-- resolves to this language (at ADDON_LOADED, again at PLAYER_LOGIN), then drops
-- ns.LOCALES. On a client in this language it also fills ns.L at file load (the default
-- "auto"). Values are strings only, with the same keys and the same format arguments, in
-- the same order, as enUS.lua (tests/test_locales.lua). Short words: the bar, the tooltip
-- rows, option labels, buttons and menu entries must fit.
-- Any UTF-8 character (the client of this language draws its script: see
-- C.LANGUAGES_NATIVE_ONLY and tests/check_encoding.lua NATIVE_LOCALES).
local _, ns = ...
local CODE = "zhTW"
local L = {}

-- General and chat
L.ADDON_TITLE             = "TruePlayed"
L.CHAT_PREFIX             = "|cff8b5cf6TruePlayed|r: "
L.FIRST_RUN               = "把經驗條拖到你想要的位置，然後右鍵 > 鎖定。滑鼠指向可看詳情（Shift：更多），點擊可看統計。設定：/tpl"
L.ON                      = "開"
L.OFF                     = "關"
L.EXCL_STATE_FMT          = "%s：%s"  -- [fmt] exclusion label (MENU_EXCLUDE_*), ON/OFF
L.CITY_ADDED_FMT          = "%s 現在計為城市。"  -- [fmt] zone name
L.CITY_REMOVED_FMT        = "%s 不再計為城市。"  -- [fmt] zone name
L.NO_ZONE                 = "目前區域未知，請稍後再試。"
L.CITY_INSTANCE           = "副本永遠不計為城市。"
L.UNKNOWN_CMD_FMT         = "未知指令「%s」。請輸入 /tpl help。"  -- [fmt] command
L.SYNC_REQUESTED          = "正在向伺服器請求 /played..."
L.SYNCED                  = "/played 已同步。"
L.SYNC_THROTTLED          = "請等幾秒後再請求。"
L.RESET_POS_DONE          = "位置已重置。"
L.RESET_SESSION_DONE      = "本次上線已重置。"
L.RESET_RATE_DONE         = "每小時經驗已重置。"
L.RESET_CHAR_DONE_FMT     = "已清除 %s 的資料。"  -- [fmt] character name
L.WIDGET_SHOWN            = "經驗條已顯示。"
L.WIDGET_HIDDEN           = "經驗條已隱藏。輸入 /tpl show 重新顯示。"
L.LOCKED                  = "經驗條已鎖定。"
L.UNLOCKED                = "經驗條已解鎖：拖曳即可移動。"
L.THEME_SET_FMT           = "主題：%s"  -- [fmt] THEME_* name
L.THEME_LIST_FMT          = "主題：%s。可選：%s"  -- [fmt] THEME_* name of the setting, theme keys (/tpl theme <key>)
L.LANG_SET_FMT            = "語言：%s。輸入 /reload 生效。"  -- [fmt] LANG_* name
L.LANG_LIST_FMT           = "語言：%s。可選：%s。變更在 /reload 後生效。"  -- [fmt] LANG_* name of the setting, accepted values (/tpl lang <value>)
L.DEBUG_ON                = "除錯訊息已開啟。"
L.DEBUG_OFF               = "除錯訊息已關閉。"
L.SCHEMA_NEWER            = "你的資料由較新版本的 TruePlayed 儲存。請更新插件；記錄已暫停。"
L.READONLY_ACTION         = "無法使用：你的資料來自較新版本的 TruePlayed（唯讀模式）。"
L.NOT_READY               = "TruePlayed 未完成載入（見錯誤視窗）。"
L.COMBAT_DEFERRED         = "設定將在戰鬥結束後開啟。"
L.EST_RECOVERED_FMT       = "已找回自上次存檔以來缺少的遊戲時間 %s（當機或未用 TruePlayed 遊戲）。其分布依你的習慣估算。"  -- [fmt] duration
L.THEME_FONT_MISSING      = "無法載入主題字型（%s）；改用遊戲字型。更新後請重新啟動遊戲。"  -- [fmt] font file name (printed once per session, after CHAT_PREFIX)
L.WTFIX_PROTECTED         = "WTFix 每次載入都會把 TruePlayed 的資料還原成舊副本，你最近的遊戲記錄會遺失。輸入 /wtfix 並取消勾選 TruePlayed：這樣 TruePlayed 會保留自己的資料，並與伺服器的 /played 重新同步。"

-- Help
L.HELP_HEADER             = "指令："
L.HELP_OPTIONS            = "/tpl - 設定"
L.HELP_STATS              = "/tpl stats [levels | zones | sessions] - 統計視窗"
L.HELP_LOCK               = "/tpl lock | unlock - 鎖定或移動經驗條"
L.HELP_SHOW               = "/tpl show | hide - 顯示或隱藏經驗條"
L.HELP_THEME              = "/tpl theme [名稱] - 查看或變更主題"
L.HELP_LANG               = "/tpl lang [%s] - 查看或變更 TruePlayed 的語言（/reload 後生效）"
L.HELP_EXCLUDE            = "/tpl afk | inn | city [on | off] - 排除設定（無參數：切換）"
L.HELP_CITY               = "/tpl citytoggle - 將目前區域計為城市（或取消）"
L.HELP_PLAYED             = "/tpl played - 在聊天框顯示摘要"
L.HELP_SYNC               = "/tpl sync - 重新整理伺服器 /played"
L.HELP_RESET              = "/tpl reset pos | session | rate | char - 重置經驗條位置、本次上線或每小時經驗，或清除此角色（需確認）"
L.HELP_DEBUG              = "/tpl debug - 除錯訊息"
L.HELP_PERF               = "/tpl perf - TruePlayed 使用的記憶體和 CPU"

-- /tpl played summary
L.SUM_HEADER_FMT          = "%s - %d 級"  -- [fmt] name, level
L.SUM_PLAYED_FMT          = "遊戲時間：%s（伺服器 /played：%s）"  -- [fmt] filtered, server
L.SUM_EXCLUDED_FMT        = "已排除：%s（%s）"  -- [fmt] duration, mask label
L.SUM_LEVEL_FMT           = "本級：%s · 每級平均：%s"  -- [fmt] durations
L.SUM_ETA_FMT             = "%s 後升級，速度 %s"  -- [fmt] ETA, rate
L.SUM_ETA_NONE            = "下一級：資料不足。"
L.SUM_MAX                 = "已達到滿級。"
L.SUM_CAP_FMT             = "%d 級：伺服器目前等級上限。經驗記錄會自動恢復。"  -- [fmt] level (detected server level cap)

-- /tpl perf
L.PERF_HEADER_FMT         = "TruePlayed %s - 效能（用戶端 %d）："  -- [fmt] version, interface
L.PERF_MEM_FMT            = "記憶體（程式碼 + 所有角色的儲存資料）：%s KB"  -- [fmt] number
L.PERF_MEM_NA             = "記憶體：此用戶端無法使用。"
L.PERF_CPU_FMT            = "CPU：載入後 %s 毫秒（每分鐘 %s 毫秒）"  -- [fmt] numbers
L.PERF_CPU_OFF            = "CPU：輸入 /console scriptProfile 1 然後 /reload 進行測量。這會拖慢遊戲：測完請改回 0。"
L.PERF_PROFILER_FMT       = "效能分析：平均每幀 %s 毫秒，峰值 %s 毫秒"  -- [fmt] numbers
L.PERF_DATA_FMT           = "此角色資料：等級 %d，區域 %d，上線記錄 %d。角色：%d"  -- [fmt] counts (label form: no plural agreement)
L.PERF_TICK_ARMED_FMT     = "正在測量接下來的 %d 秒..."  -- [fmt] ticks
L.PERF_TICK_FMT           = "Tick：平均 %s 毫秒，最多 %s 毫秒（共 %d 次）"  -- [fmt] numbers, count

-- Formats
L.DUR_D_H                 = "%d天%02d時"  -- [fmt] days, hours
L.DUR_H_M                 = "%d時%02d分"  -- [fmt] hours, minutes
L.DUR_H                   = "%d小時"  -- [fmt] hours
L.DUR_M                   = "%d分"  -- [fmt] minutes
L.DUR_LT_1M               = "<1分"
L.DUR_LONG_DHM            = "%d天%d時%02d分"  -- [fmt]
L.DUR_LONG_HM             = "%d時%02d分"  -- [fmt]
L.DUR_LONG_M              = "%d分鐘"  -- [fmt]
L.ETA_FMT                 = "~%s"  -- [fmt] duration
L.ETA_LT_1M               = "<1分"
L.AGO_FMT                 = "%s前"  -- [fmt] duration
L.DECIMAL_SEP             = "."
L.THOUSANDS_SEP           = ","
L.NUM_K                   = "%sk"  -- [fmt] number text
L.NUM_M                   = "%sM"  -- [fmt] number text
L.PERCENT_FMT             = "%s%%"  -- [fmt] number text
L.PER_HOUR                = "/時"
L.FPS_FMT                 = "%s fps"  -- [fmt] coloured number
L.MS_FMT                  = "%s ms"  -- [fmt] coloured number
L.DATE_FMT                = "%Y/%m/%d"  -- date() pattern
L.DATETIME_FMT            = "%m/%d %H:%M"  -- date() pattern
L.DOTS                    = "..."
L.SEP                     = " · "
L.RANGE_FMT               = "%s » %s"  -- [fmt] from, to

-- Tokens (option labels) and token texts
L.TOKEN_NONE              = "無"
L.TOKEN_ETA               = "升級所需時間"
L.TOKEN_XPH               = "每小時經驗"
L.TOKEN_PCTH              = "每小時升級百分比"
L.TOKEN_XPLEFT            = "剩餘經驗"
L.TOKEN_RESTED            = "休息經驗"
L.TOKEN_LEVEL_TIME        = "本級用時"
L.TOKEN_SESSION           = "本次上線時間"
L.TOKEN_PLAYED            = "遊戲時間（已過濾）"
L.TOKEN_PLAYED_SERVER     = "伺服器 /played"
L.TOKEN_AFK_SESSION       = "本次暫離時間"
L.TOKEN_AVG_LEVEL         = "每級平均用時"
L.TOKEN_ZONE_TIME         = "目前區域時間"
L.TOKEN_FPS               = "FPS"
L.TOKEN_LATENCY           = "延遲"
L.TOKEN_FPS_LATENCY       = "FPS + 延遲"
L.TOKEN_KILLS             = "升級需殺怪數"
L.TOKEN_ETA_KILLS         = "升級時間 + 殺怪數"
L.TOKEN_INSTANCE_SESSION  = "本次副本時間"
L.TOKEN_INSTANCE_TOTAL    = "副本總時間"
L.PFX_LEVEL_FMT           = "本級 %s"  -- [fmt] duration
L.PFX_SESSION_FMT         = "本次 %s"  -- [fmt] duration
L.PFX_PLAYED_FMT          = "總計 %s"  -- [fmt] duration
L.PFX_SERVER_FMT          = "/played %s"  -- [fmt] duration
L.PFX_AFK_FMT             = "暫離 %s"  -- [fmt] duration
L.PFX_AVG_FMT             = "平均 %s/級"  -- [fmt] duration
L.PFX_ZONE_FMT            = "區域 %s"  -- [fmt] duration
L.PFX_INST_SESSION_FMT    = "副本 %s"  -- [fmt] duration (instances this session)
L.PFX_INST_TOTAL_FMT      = "副本總計 %s"  -- [fmt] duration (instances, whole character)
L.XPLEFT_FMT              = "還需 %s 經驗"  -- [fmt] number
L.RESTED_FMT              = "休息 %s"  -- [fmt] percent text
L.PCTH_FMT                = "%s%%/時"  -- [fmt] number text
L.KILLS_FMT               = "%s隻怪"  -- [fmt] number text
L.KILLS_ONE_FMT           = "%s隻怪"  -- [fmt] number text (exactly 1)
L.STALL_MARK              = "*"  -- after a frozen XP per hour / time to level (no XP for a while)
L.CAP_SHORT               = "伺服器上限"  -- XP infos at a detected server level cap

-- Widget
L.LEVEL_SHORT_FMT         = "等級 %d"  -- [fmt] level
L.LEVEL_PCT_FMT           = "等級 %d · %s"  -- [fmt] level, percent text
L.LEVEL_CAP_FMT           = "等級 %d · 上限"  -- [fmt] level (detected server level cap)
L.XP_FMT                  = "經驗：%s / %s"  -- [fmt] numbers
L.XP_BARE_FMT             = "%s / %s"  -- [fmt] numbers (narrow bar: the XP label is dropped)
L.XP_LABEL                = "經驗："  -- themes with split texts: label before the XP numbers (XP_BARE_FMT)
L.LEVEL_TITLE_FMT         = "等級 %d"  -- [fmt] level (themes with title-case level texts)
L.LEVEL_CAP_TAG           = "上限"  -- themes: detected server level cap, after the level (upper case)
L.LEVEL_CAP_TAG_TITLE     = "上限"  -- themes: detected server level cap, after LEVEL_TITLE_FMT
L.UNLOCKED_HINT           = "拖曳以移動 · 右鍵：選單"
L.MAX_LEVEL               = "滿級"

-- Tooltip
L.TT_LEVEL_FMT            = "等級 %d » %d"  -- [fmt] level, next level
L.TT_XP                   = "經驗"
L.TT_REMAINING            = "剩餘"
L.TT_RESTED               = "休息"
L.TT_RESTED_FMT           = "%s 經驗（%s）"  -- [fmt] number, percent of the level
L.TT_NEXT_LEVEL           = "下一級"
L.TT_XPH                  = "每小時經驗"
L.TT_KILLS                = "需殺怪數"
L.TT_KILLS_FMT            = "~%s（平均 %s，最近 %s 經驗）"  -- [fmt] count, average XP of the last 10 kills, XP of the last kill (both without rested bonus)
L.TT_KILLS_NODATA         = "下次擊殺後顯示"
L.TT_RATES_FMT            = "本次 %s · 本級 %s"  -- [fmt] rates
L.TT_WARMING_FMT          = "~%s 後提供估算"  -- [fmt] duration
L.TT_NO_RATE              = "資料不足"
L.TT_NODATA_FMT           = "計入遊戲約 %s 後可用"  -- [fmt] duration
L.TT_NODATA_XP            = "首次獲得經驗後可用"
L.RATE_ESTIMATE           = "依你的 /played 估算"
L.TT_SRC_LEVEL            = "依本級至今"
L.TT_SRC_RECENT           = "依最近幾級"
L.TT_PAUSED_FMT           = "計時暫停：已排除%s"  -- [fmt] PAUSE_*
L.PAUSE_AFK               = "暫離時間"
L.PAUSE_INN               = "旅店時間"
L.PAUSE_CITY              = "城市時間"
L.MASK_AFK                = "暫離"
L.MASK_INN                = "旅店"
L.MASK_CITY               = "城市"
L.TT_READONLY             = "唯讀：來自較新版本的資料"
L.TT_EXCL_FMT             = "不含%s"  -- [fmt] mask label
L.TT_SESSION              = "本次上線"
L.TT_THIS_LEVEL           = "本級"
L.TT_ZONE_FMT             = "區域：%s"  -- [fmt] zone name
L.TT_PLAYED               = "遊戲時間"
L.TT_PLAYED_EXCL_FMT      = "遊戲時間（不含%s）"  -- [fmt] mask label
L.TT_PREINSTALL_FMT       = "含安裝前 %s，未過濾"  -- [fmt] duration
L.TT_EST_FMT              = "含當機後重建的 %s"  -- [fmt] duration
L.TT_SERVER               = "伺服器 /played"
L.TT_SERVER_AGE_FMT       = "%s（%s）"  -- [fmt] duration, AGO text
L.TT_AVG_LEVEL            = "每級平均"
L.TT_AVG_RECENT_FMT       = "最近 %d 級平均"  -- [fmt] count (always >= 2)
L.TT_BREAKDOWN            = "分布"
L.BD_PART_FMT             = "%s %s"  -- [fmt] part label (BD_*), percent
L.BD_WORLD                = "野外"
L.BD_DUNGEON              = "地城"
L.BD_RAID                 = "團隊副本"
L.BD_PVP                  = "PvP"
L.BD_TAXI                 = "飛行"
L.BD_AFK                  = "暫離"
L.BD_INN                  = "旅店"
L.BD_CITY                 = "城市"
L.TT_INSTANCES            = "副本中"
L.TT_HINT                 = "Shift：詳情 · 點擊：統計 · 右鍵：選單"
L.TT_HINT_COMPARTMENT     = "Shift：詳情 · 點擊：設定 · 右鍵：統計"
L.TT_MAX_LEVEL            = "已達到滿級"
L.TT_CAP_FMT              = "%d 級：伺服器目前等級上限（最近 %d 隻怪沒有經驗）"  -- [fmt] level, mobs killed without XP (3 or more)
L.TT_CAP_RESUME           = "伺服器重新給予經驗後，經驗記錄會自動恢復。"
L.TT_STALLED_FMT          = "%s 每小時經驗已凍結：已有 %s 遊戲時間未獲得經驗"  -- [fmt] STALL_MARK, duration of counted play
L.TT_STALLED_RESUME       = "下次獲得經驗時恢復；無經驗的時間不計入。"
L.TT_TOP_ZONES            = "本級主要區域"
L.TT_TOP_CITIES           = "常去主城"
L.SECTION_CONTINENTS      = "大陸"
L.CONT_INSTANCES          = "副本"
L.CONT_OTHER              = "其他"
L.TT_OF_WHICH_AFK_FMT     = "%s（暫離 %s）"  -- [fmt] durations
L.TT_LAST_LEVELS          = "最近等級"
L.TT_LEVEL_ROW_FMT        = "等級 %d"  -- [fmt] level
L.TT_INN                  = "旅店 / 休息區"
L.TT_CITY                 = "城市"
L.TT_AFK                  = "暫離"
L.TT_TAXI                 = "飛行"
L.TT_DEATHS               = "死亡"
L.TT_UNTRACKED            = "安裝前 / 未記錄"
L.TT_UNTRACKED_NOTE       = "未細分"
L.TT_EST_TOTAL            = "當機後重建"
L.TT_EST_NOTE             = "估算分布"
L.TT_ACCOUNT_FMT          = "帳號（%d 個角色）"  -- [fmt] count (2 or more)
L.TT_ACCOUNT_ONE_FMT      = "帳號（%d 個角色）"  -- [fmt] count (1)
L.TT_ACCOUNT_INST         = "帳號，副本中"
L.TT_NET                  = "FPS · 本地 · 世界"
L.TT_NET_FMT              = "%s · %s · %s"  -- [fmt] fps, home, world

-- Context menu
L.MENU_EXCLUDE_AFK        = "排除暫離時間"
L.MENU_EXCLUDE_INN        = "排除旅店 / 休息區時間"
L.MENU_EXCLUDE_CITY       = "排除城市時間"
L.MENU_LOCK               = "鎖定"
L.MENU_THEME              = "主題"
L.MENU_STATS              = "統計..."
L.MENU_RESET_SESSION      = "重置本次上線"
L.MENU_HIDE               = "隱藏"
L.MENU_OPTIONS            = "設定..."

-- Options panel
L.OPT_EXCLUSIONS          = "排除"
L.OPT_EXCLUSIONS_HELP     = "排除只改變顯示：不會刪除任何資料，一切都會立即重新計算。"
L.OPT_CITY_HELP           = "城市：暴風城、鐵爐堡、達納蘇斯、奧格瑪、雷霆崖、幽暗城（/tpl citytoggle 可新增或移除目前區域）。旅店 / 休息區：其他任何休息區。"
L.OPT_DISPLAY             = "顯示"
L.OPT_THEME               = "主題"
L.OPT_THEME_NOTE          = "改變經驗條、其提示框、圖表和統計視窗的外觀。下方選擇的顏色會取代主題本身的顏色。"
L.OPT_THEME_RESTART_NOTE  = "安裝或更新 TruePlayed 後，請重新啟動遊戲（僅 /reload 不夠），以載入主題的字型和材質。"
L.OPT_SHOW                = "顯示經驗條"
L.OPT_SLOT1               = "資訊 1（大）"
L.OPT_SLOT2               = "資訊 2"
L.OPT_SLOT3               = "資訊 3"
L.OPT_SLOT3_POS           = "資訊 3 位置"
L.OPT_SLOTS_NOTE          = "資訊 1 在右上，資訊 2 在經驗之後，資訊 3 在上方。"
L.POS_CENTER              = "上方置中"
L.POS_LEFT                = "上方靠左"
L.OPT_PCT_POS             = "等級百分比"
L.PCT_FOLLOW              = "跟隨經驗條"
L.PCT_LEVEL               = "在等級旁"
L.OPT_MAX_SLOTS           = "滿級時，將經驗資訊取代為："
L.OPT_MAX_SLOT_FMT        = "滿級資訊 %d"  -- [fmt] slot index
L.OPT_WIDTH               = "寬度"
L.OPT_HEIGHT              = "經驗條高度"
L.OPT_SCALE               = "縮放"
L.OPT_FONT_SIZE           = "文字大小"
L.OPT_LOCK                = "鎖定位置"
L.OPT_COMBAT_HIDE         = "戰鬥中隱藏"
L.OPT_FADE                = "滑鼠移開時淡出"
L.OPT_HIDE_MAX            = "滿級時隱藏"
L.OPT_LANGUAGE            = "語言 (Language)"
L.OPT_LANGUAGE_NOTE       = "TruePlayed 的語言在重新載入介面後變更（下方按鈕或 /reload）。遊戲提供的名稱（區域、怪物、副本、角色）保持遊戲用戶端的語言。"
L.OPT_RELOAD              = "重新載入介面"
L.LANG_AUTO               = "自動"
L.LANG_ENUS               = "English"
L.LANG_FRFR               = "Français"
L.LANG_DEDE               = "Deutsch"
L.LANG_ESES               = "Español (EU)"
L.LANG_ESMX               = "Español (AL)"
L.LANG_ITIT               = "Italiano"
L.LANG_PTBR               = "Português (BR)"
L.LANG_RURU               = "\208\160\209\131\209\129\209\129\208\186\208\184\208\185"  -- Russian, in Cyrillic (escaped: this file is Latin-1)
L.LANG_KOKR               = "\237\149\156\234\181\173\236\150\180"  -- Korean, in Hangul (escaped)
L.LANG_ZHCN               = "\231\174\128\228\189\147\228\184\173\230\150\135"  -- Simplified Chinese (escaped)
L.LANG_ZHTW               = "\231\185\129\233\171\148\228\184\173\230\150\135"  -- Traditional Chinese (escaped)
L.OPT_TEXTS               = "文字"
L.OPT_TEXT_COLOR          = "文字顏色"
L.OPT_TEXT_COLOR_RESET    = "主題顏色"
L.OPT_TEXT_COLOR_NOTE     = "套用於經驗條上的所有文字。經驗條本身的顏色在下方設定。"
L.OPT_OUTLINE             = "文字描邊"
L.OUTLINE_NONE            = "無"
L.OUTLINE_THIN            = "細"
L.OUTLINE_THICK           = "粗"
L.OPT_SHADOW              = "文字陰影"
L.OPT_BG_ALPHA            = "背景不透明度"
L.OPT_BAR_COLORS          = "經驗條配色"
L.OPT_XP_COLOR            = "經驗顏色"
L.OPT_RESTED_COLOR        = "休息經驗顏色"
L.OPT_BAR_COLORS_RESET    = "主題顏色"
L.OPT_BAR_COLORS_NOTE     = "在你自選顏色之前，經驗條使用主題的顏色。處於休息狀態時，經驗條變為休息經驗顏色，較淺的色調顯示休息經驗能延伸到哪裡。滿級時經驗條以經驗顏色填滿並變暗。"
L.OPT_NET                 = "FPS 和延遲"
L.OPT_QUALITY_COLORS      = "品質顏色（綠、黃、紅）"
L.OPT_QUALITY_COLORS_NOTE = "取消勾選後，FPS 和延遲使用文字顏色。"
L.OPT_GRAPH_WINDOW        = "圖表時長"
L.OPT_GRAPH_NOTE          = "將滑鼠指向經驗條上的 FPS 或延遲可查看圖表，再指向圖表讀取數值。遊戲大約每 30 秒才更新一次延遲。"
L.OPT_CALC                = "計算"
L.OPT_REACTIVITY          = "每小時經驗反應速度"
L.OPT_REACTIVITY_HELP     = "每小時經驗跟隨你近期節奏的快慢。"
L.REACT_SLOW              = "慢（90分鐘）"
L.REACT_NORMAL            = "正常（60分鐘）"
L.REACT_FAST              = "快（20分鐘）"
L.OPT_REQUEST_PLAYED      = "登入時向伺服器請求 /played"
L.OPT_REQUEST_PLAYED_HELP = "當機後找回時間需要此項。只有當其他插件在 10 秒內沒有請求時，平常的 /played 訊息才會在聊天框出現一次。"
L.OPT_HIDE_PLAYED         = "TruePlayed 請求時隱藏 /played 訊息（實驗性）"
L.OPT_HIDE_PLAYED_HELP    = "在 TruePlayed 自己的請求進行期間，短暫攔截聊天框中的 /played 顯示。你自己輸入的 /played 一律會顯示。可能在地城中干擾聊天：如果看到聊天錯誤，請關閉此項。"
L.OPT_HIDE_PLAYED_NA      = "此用戶端無法使用。"
L.OPT_CITIES              = "城市"
L.OPT_CITY_CURRENT_FMT    = "目前區域：%s（%s）"  -- [fmt] zone name, CITY_YES/CITY_NO
L.CITY_YES                = "計為城市"
L.CITY_NO                 = "不是城市"
L.OPT_CITY_TOGGLE         = "將此區域計為城市 / 取消"
L.OPT_DATA                = "資料"
L.OPT_OPEN_STATS          = "統計..."
L.OPT_RESET_POS           = "重置位置"
L.OPT_RESET_SESSION       = "重置本次上線"
L.OPT_RESET_RATE          = "重置每小時經驗"
L.OPT_RESET_CHAR          = "清除此角色的資料"
L.CONFIRM_ERASE_CHAR_FMT  = "清除 %s 的所有 TruePlayed 資料？此操作無法復原。"  -- [fmt] name
L.ERASE_YES               = "是"  -- the erase popup's buttons (the game's YES / NO follow the client)
L.ERASE_NO                = "否"
L.OPT_NOTE_PREINSTALL     = "安裝 TruePlayed 之前的遊戲時間無法細分，也永遠不會被排除。"
L.OPT_NOTE_IDLE           = "遊戲自動將你標記為暫離之前的幾分鐘仍計為活躍時間。"
L.OPT_NOTE_CRASH          = "遊戲當機後（或未用 TruePlayed 遊戲後），缺少的時間會從伺服器 /played 找回，並依你自己的習慣分配；它會被標記為重建。"
L.OPT_NOTE_CITY           = "城市時間依地圖計算：整個主城都計為城市，而不只是旅店。"
L.OPT_NOTE_STALL_FMT      = "連續 %d 分鐘遊戲沒有任何經驗後（等級上限、在城裡長時間休息...），每小時經驗和升級時間會凍結：這段時間不計入，下次獲得經驗時恢復。"  -- [fmt] minutes
L.OPT_NOTE_CAP_FMT        = "當連續 %d 隻怪不給經驗時，會識別為有暫時等級上限的伺服器（測試服）：經驗條會顯示為滿級樣式，經驗恢復後自動恢復正常。"  -- [fmt] mobs
L.OPT_NOTE_READONLY       = "唯讀：你的資料由較新版本的 TruePlayed 儲存。請更新插件；在此之前不會記錄任何內容。"
L.OPT_VERSION_FMT         = "版本 %s"  -- [fmt] version
L.SLIDER_PX_FMT           = "%d px"  -- [fmt] value
L.SLIDER_PCT_FMT          = "%d%%"  -- [fmt] value

-- Themes (display names: options dropdown, context menu, /tpl theme)
L.THEME_FUTURISTE         = "未來"
L.THEME_ACTUEL            = "經典"
L.THEME_HEROIC            = "英雄奇幻"
L.THEME_PIXEL             = "像素（復古）"
L.THEME_CLASS             = "職業（自動）"
L.THEME_WARRIOR           = "戰士"
L.THEME_PALADIN           = "聖騎士"
L.THEME_HUNTER            = "獵人"
L.THEME_ROGUE             = "盜賊"
L.THEME_PRIEST            = "牧師"
L.THEME_SHAMAN            = "薩滿"
L.THEME_MAGE              = "法師"
L.THEME_WARLOCK           = "術士"
L.THEME_DRUID             = "德魯伊"

-- Statistics window
L.WIN_TITLE               = "TruePlayed - 統計"
L.VIEW_ACCOUNT            = "帳號（所有角色）"
L.WIN_ERASE               = "清除..."
L.WIN_FILTER_FMT          = "顯示時間不含%s"  -- [fmt] mask label
L.TAB_LEVELS              = "等級"
L.TAB_ZONES               = "區域"
L.TAB_SESSIONS            = "上線記錄"
L.COL_LEVEL               = "等級"
L.COL_TIME                = "時間"
L.COL_SERVER              = "伺服器"
L.COL_XPH                 = "經驗/時"
L.COL_AFK                 = "暫離"
L.COL_INN                 = "旅店"
L.COL_CITY                = "城市"
L.COL_INST                = "副本"
L.COL_MAIN_ZONE           = "主要區域"
L.COL_REACHED             = "達成"
L.COL_ZONE                = "區域"
L.COL_RAW                 = "原始"
L.COL_XP                  = "經驗"
L.COL_DATE                = "日期"
L.COL_DURATION            = "時長"
L.COL_LEVELS              = "等級"
L.COL_DEATHS              = "死亡"
L.COL_CHARS               = "角色"
L.COL_AVG                 = "平均"
L.ROW_IN_PROGRESS         = "進行中"
L.ROW_PARTIAL_TIP         = "該等級開始於安裝 TruePlayed 之前。"
L.ROW_REC_TIP             = "在當機期間或未啟用 TruePlayed 時達成：時間依伺服器 /played 和你的經驗估算。"
L.ROW_EST_TIP_FMT         = "含當機後重建的 %s（估算分布）。"  -- [fmt] duration
L.ROW_GAP_TIP_FMT         = "伺服器時間比記錄時間多 %s（未細分）。"  -- [fmt] duration
L.ROW_ZONES_FMT           = "%d 級時的區域"  -- [fmt] level
L.ROW_ZONES_EMPTY         = "此等級沒有記錄區域。"
L.LEVELS_HOVER_HINT       = "滑鼠指向等級可查看其區域。"
L.FOOTER_FMT              = "每級平均：%s · 最近 %d 級：%s · 總計：%s"  -- [fmt] dur, count, dur, dur
L.FOOTER_ACCOUNT_FMT      = "帳號每級平均：%s（%d 個角色）"  -- [fmt] dur, count (2 or more)
L.FOOTER_ACCOUNT_ONE_FMT  = "帳號每級平均：%s（%d 個角色）"  -- [fmt] dur, count (1)
L.FOOTER_ACCOUNT_NONE     = "帳號每級平均：資料不足"
L.CITIES_HEADER           = "常去主城"
L.INSTANCES_HEADER        = "最常進入的副本"
L.INST_ROW_FMT            = "%s（%s）"  -- [fmt] instance name, KIND_*
L.KIND_DUNGEON            = "地城"
L.KIND_RAID               = "團隊副本"
L.KIND_PVP                = "PvP"
L.FOOTER_INST_FMT         = "副本中：%s"  -- [fmt] duration
L.NO_DATA                 = "尚無資料。"
L.NO_SESSIONS_ACCOUNT     = "上線記錄依角色列出。"
L.CITY_MARK               = "（城市）"
L.CHAR_FMT                = "%s - %d 級"  -- [fmt] name, level
L.ZONE_UNKNOWN            = "未知區域"
L.ZONE_OTHER              = "其他區域"

-- FPS / latency graph (Graph.lua)
L.GRAPH_TITLE_FMT         = "FPS 和延遲（%s）"  -- [fmt] GRAPH_WINDOW_*
L.GRAPH_WINDOW_30         = "30秒"
L.GRAPH_WINDOW_60         = "1分鐘"
L.GRAPH_WINDOW_300        = "5分鐘"
L.GRAPH_AGO_FMT           = "%s前：%s · %s"  -- [fmt] age (GRAPH_AGE_*), FPS text, latency text
L.GRAPH_AGE_S_FMT         = "%d秒"  -- [fmt] seconds (age below one minute)
L.GRAPH_AGE_MS_FMT        = "%d分%02d秒"  -- [fmt] minutes, seconds
L.GRAPH_MIN_AVG_MAX_FMT   = "最低 %s · 平均 %s · 最高 %s"  -- [fmt] values
L.GRAPH_LAT_NOTE          = "遊戲大約每 30 秒才更新一次延遲：因此畫成階梯狀。"
L.GRAPH_NO_DATA           = "正在收集資料..."

-- Registration for Core's language switch. Keep this block LAST: a string defined
-- below it would miss the file-load copy into ns.L on a client in this language.
local reg = ns.LOCALES
if type(reg) ~= "table" then
  reg = {}
  ns.LOCALES = reg
end
reg[CODE] = L
-- The default ("auto") on a client in this language: this language from file load on.
if GetLocale() == CODE then
  local dst = ns.L
  if type(dst) == "table" then
    for k, v in pairs(L) do dst[k] = v end
  end
end
