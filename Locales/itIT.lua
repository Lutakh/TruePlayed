-- Locales/itIT.lua - Italian strings of TruePlayed (complete translation).
-- A copy of frFR.lua (see the recipe at the top of enUS.lua): it builds its own table and
-- registers it as ns.LOCALES[CODE]; Core applies it into ns.L when the "language" setting
-- resolves to this language (at ADDON_LOADED, again at PLAYER_LOGIN), then drops
-- ns.LOCALES. On a client in this language it also fills ns.L at file load (the default
-- "auto"). Values are strings only, with the same keys and the same format arguments, in
-- the same order, as enUS.lua (tests/test_locales.lua). Short words: the bar, the tooltip
-- rows, option labels, buttons and menu entries must fit.
-- Latin-1 characters only (see SPEC-FINAL 2.6); the names of the native-only languages
-- are decimal escapes.
local _, ns = ...
local CODE = "itIT"
local L = {}

-- General and chat
L.ADDON_TITLE             = "TruePlayed"
L.CHAT_PREFIX             = "|cff8b5cf6TruePlayed|r: "
L.FIRST_RUN               = "Trascina la barra dove vuoi, poi clic destro > Blocca. Passaci sopra col mouse per i dettagli (Maiusc: di più), cliccala per le statistiche. Opzioni: /tpl"
L.ON                      = "attivo"
L.OFF                     = "disattivo"
L.EXCL_STATE_FMT          = "%s: %s"  -- [fmt] exclusion label (MENU_EXCLUDE_*), ON/OFF
L.CITY_ADDED_FMT          = "%s ora conta come città."  -- [fmt] zone name
L.CITY_REMOVED_FMT        = "%s non conta più come città."  -- [fmt] zone name
L.NO_ZONE                 = "Zona attuale sconosciuta, riprova tra un attimo."
L.CITY_INSTANCE           = "Le istanze non contano mai come città."
L.UNKNOWN_CMD_FMT         = "Comando sconosciuto «%s». Digita /tpl help."  -- [fmt] command
L.SYNC_REQUESTED          = "Richiesta del /played al server..."
L.SYNCED                  = "/played sincronizzato."
L.SYNC_THROTTLED          = "Attendi qualche secondo prima di chiedere di nuovo."
L.RESET_POS_DONE          = "Posizione reimpostata."
L.RESET_SESSION_DONE      = "Sessione reimpostata."
L.RESET_RATE_DONE         = "XP all'ora reimpostati."
L.RESET_CHAR_DONE_FMT     = "Dati di %s cancellati."  -- [fmt] character name
L.WIDGET_SHOWN            = "Barra mostrata."
L.WIDGET_HIDDEN           = "Barra nascosta. Digita /tpl show per farla riapparire."
L.LOCKED                  = "Barra bloccata."
L.UNLOCKED                = "Barra sbloccata: trascinala per spostarla."
L.THEME_SET_FMT           = "Tema: %s"  -- [fmt] THEME_* name
L.THEME_LIST_FMT          = "Tema: %s. Disponibili: %s"  -- [fmt] THEME_* name of the setting, theme keys (/tpl theme <key>)
L.LANG_SET_FMT            = "Lingua: %s. Digita /reload per applicarla."  -- [fmt] LANG_* name
L.LANG_LIST_FMT           = "Lingua: %s. Disponibili: %s. Una modifica vale dopo /reload."  -- [fmt] LANG_* name of the setting, accepted values (/tpl lang <value>)
L.DEBUG_ON                = "Messaggi di debug attivi."
L.DEBUG_OFF               = "Messaggi di debug disattivati."
L.SCHEMA_NEWER            = "I tuoi dati sono stati salvati da una versione più recente di TruePlayed. Aggiorna l'addon; il conteggio è in pausa."
L.READONLY_ACTION         = "Non disponibile: i tuoi dati vengono da una versione più recente di TruePlayed (sola lettura)."
L.NOT_READY               = "TruePlayed non ha finito di caricarsi (vedi la finestra degli errori)."
L.COMBAT_DEFERRED         = "Le opzioni si apriranno dopo il combattimento."
L.EST_RECOVERED_FMT       = "Recuperati %s di tempo di gioco mancante dall'ultimo salvataggio (crash o gioco senza TruePlayed). La ripartizione è stimata in base alle tue abitudini."  -- [fmt] duration
L.THEME_FONT_MISSING      = "Impossibile caricare un carattere del tema (%s); viene usato quello del gioco. Riavvia il gioco dopo un aggiornamento."  -- [fmt] font file name (printed once per session, after CHAT_PREFIX)
L.WTFIX_PROTECTED         = "WTFix riporta i dati di TruePlayed a una copia precedente a ogni caricamento, quindi perderesti la cronologia di gioco recente. Digita /wtfix e togli la spunta a TruePlayed: così TruePlayed tiene i propri dati e si risincronizza col /played del server."

-- Help
L.HELP_HEADER             = "Comandi:"
L.HELP_OPTIONS            = "/tpl - opzioni"
L.HELP_STATS              = "/tpl stats [levels | zones | sessions] - finestra delle statistiche"
L.HELP_LOCK               = "/tpl lock | unlock - blocca o sposta la barra"
L.HELP_SHOW               = "/tpl show | hide - mostra o nascondi la barra"
L.HELP_THEME              = "/tpl theme [nome] - mostra o cambia il tema"
L.HELP_LANG               = "/tpl lang [%s] - mostra o cambia la lingua di TruePlayed (dopo /reload)"
L.HELP_EXCLUDE            = "/tpl afk | inn | city [on | off] - esclusioni (senza argomento: alterna)"
L.HELP_CITY               = "/tpl citytoggle - conta la zona attuale come città (o no)"
L.HELP_PLAYED             = "/tpl played - riepilogo in chat"
L.HELP_SYNC               = "/tpl sync - aggiorna il /played del server"
L.HELP_RESET              = "/tpl reset pos | session | rate | char - reimposta la posizione della barra, la sessione o gli XP all'ora, o cancella questo personaggio (chiede conferma)"
L.HELP_DEBUG              = "/tpl debug - messaggi di debug"
L.HELP_PERF               = "/tpl perf - memoria e CPU usate da TruePlayed"

-- /tpl played summary
L.SUM_HEADER_FMT          = "%s - livello %d"  -- [fmt] name, level
L.SUM_PLAYED_FMT          = "Giocato: %s (/played del server: %s)"  -- [fmt] filtered, server
L.SUM_EXCLUDED_FMT        = "Escluso: %s (%s)"  -- [fmt] duration, mask label
L.SUM_LEVEL_FMT           = "Questo livello: %s · media per livello: %s"  -- [fmt] durations
L.SUM_ETA_FMT             = "Prossimo livello tra %s a %s"  -- [fmt] ETA, rate
L.SUM_ETA_NONE            = "Prossimo livello: dati ancora insufficienti."
L.SUM_MAX                 = "Livello massimo raggiunto."
L.SUM_CAP_FMT             = "Livello %d: limite di livello attuale del server. Il conteggio degli XP riprende da solo."  -- [fmt] level (detected server level cap)

-- /tpl perf
L.PERF_HEADER_FMT         = "TruePlayed %s - prestazioni (client %d):"  -- [fmt] version, interface
L.PERF_MEM_FMT            = "Memoria (codice + dati salvati di tutti i personaggi): %s KB"  -- [fmt] number
L.PERF_MEM_NA             = "Memoria: non disponibile su questo client."
L.PERF_CPU_FMT            = "CPU: %s ms dal caricamento (%s ms al minuto)"  -- [fmt] numbers
L.PERF_CPU_OFF            = "CPU: digita /console scriptProfile 1 e poi /reload per misurare. Rallenta il gioco: rimettilo a 0 dopo."
L.PERF_PROFILER_FMT       = "Profiler: %s ms per fotogramma in media, picco %s ms"  -- [fmt] numbers
L.PERF_DATA_FMT           = "Dati di questo personaggio: livelli %d, zone %d, sessioni %d. Personaggi: %d"  -- [fmt] counts (label form: no plural agreement)
L.PERF_TICK_ARMED_FMT     = "Misurazione dei prossimi %d secondi..."  -- [fmt] ticks
L.PERF_TICK_FMT           = "Tick: %s ms in media, %s ms al massimo su %d tick"  -- [fmt] numbers, count

-- Formats
L.DUR_D_H                 = "%d g %02d h"  -- [fmt] days, hours
L.DUR_H_M                 = "%d h %02d min"  -- [fmt] hours, minutes
L.DUR_H                   = "%d h"  -- [fmt] hours
L.DUR_M                   = "%d min"  -- [fmt] minutes
L.DUR_LT_1M               = "<1 min"
L.DUR_LONG_DHM            = "%d g %d h %02d min"  -- [fmt]
L.DUR_LONG_HM             = "%d h %02d min"  -- [fmt]
L.DUR_LONG_M              = "%d min"  -- [fmt]
L.ETA_FMT                 = "~%s"  -- [fmt] duration
L.ETA_LT_1M               = "<1 min"
L.AGO_FMT                 = "%s fa"  -- [fmt] duration
L.DECIMAL_SEP             = ","
L.THOUSANDS_SEP           = "."
L.NUM_K                   = "%sk"  -- [fmt] number text
L.NUM_M                   = "%sM"  -- [fmt] number text
L.PERCENT_FMT             = "%s%%"  -- [fmt] number text
L.PER_HOUR                = "/h"
L.FPS_FMT                 = "%s fps"  -- [fmt] coloured number
L.MS_FMT                  = "%s ms"  -- [fmt] coloured number
L.DATE_FMT                = "%d/%m/%Y"  -- date() pattern
L.DATETIME_FMT            = "%d/%m %H:%M"  -- date() pattern
L.DOTS                    = "..."
L.SEP                     = " · "
L.RANGE_FMT               = "%s » %s"  -- [fmt] from, to

-- Tokens (option labels) and token texts
L.TOKEN_NONE              = "Niente"
L.TOKEN_ETA               = "Tempo al prossimo livello"
L.TOKEN_XPH               = "XP all'ora"
L.TOKEN_PCTH              = "% del livello all'ora"
L.TOKEN_XPLEFT            = "XP mancanti"
L.TOKEN_RESTED            = "XP riposo"
L.TOKEN_LEVEL_TIME        = "Tempo a questo livello"
L.TOKEN_SESSION           = "Tempo di sessione"
L.TOKEN_PLAYED            = "Giocato (filtrato)"
L.TOKEN_PLAYED_SERVER     = "/played del server"
L.TOKEN_AFK_SESSION       = "AFK in questa sessione"
L.TOKEN_AVG_LEVEL         = "Tempo medio per livello"
L.TOKEN_ZONE_TIME         = "Tempo nella zona attuale"
L.TOKEN_FPS               = "FPS"
L.TOKEN_LATENCY           = "Latenza"
L.TOKEN_FPS_LATENCY       = "FPS + latenza"
L.TOKEN_KILLS             = "Mostri da uccidere"
L.TOKEN_ETA_KILLS         = "Tempo al livello + mostri"
L.TOKEN_INSTANCE_SESSION  = "Tempo in istanza (sessione)"
L.TOKEN_INSTANCE_TOTAL    = "Tempo totale in istanza"
L.PFX_LEVEL_FMT           = "Livello %s"  -- [fmt] duration
L.PFX_SESSION_FMT         = "Sessione %s"  -- [fmt] duration
L.PFX_PLAYED_FMT          = "Totale %s"  -- [fmt] duration
L.PFX_SERVER_FMT          = "/played %s"  -- [fmt] duration
L.PFX_AFK_FMT             = "AFK %s"  -- [fmt] duration
L.PFX_AVG_FMT             = "Media %s/liv."  -- [fmt] duration
L.PFX_ZONE_FMT            = "Zona %s"  -- [fmt] duration
L.PFX_INST_SESSION_FMT    = "Ist. %s"  -- [fmt] duration (instances this session)
L.PFX_INST_TOTAL_FMT      = "Ist. totale %s"  -- [fmt] duration (instances, whole character)
L.XPLEFT_FMT              = "%s XP mancanti"  -- [fmt] number
L.RESTED_FMT              = "Riposo %s"  -- [fmt] percent text
L.PCTH_FMT                = "%s%%/h"  -- [fmt] number text
L.KILLS_FMT               = "%s mostri"  -- [fmt] number text
L.KILLS_ONE_FMT           = "%s mostro"  -- [fmt] number text (exactly 1)
L.STALL_MARK              = "*"  -- after a frozen XP per hour / time to level (no XP for a while)
L.CAP_SHORT               = "Limite server"  -- XP infos at a detected server level cap

-- Widget
L.LEVEL_SHORT_FMT         = "LIV. %d"  -- [fmt] level
L.LEVEL_PCT_FMT           = "LIV. %d · %s"  -- [fmt] level, percent text
L.LEVEL_CAP_FMT           = "LIV. %d · LIMITE"  -- [fmt] level (detected server level cap)
L.XP_FMT                  = "XP: %s / %s"  -- [fmt] numbers
L.XP_BARE_FMT             = "%s / %s"  -- [fmt] numbers (narrow bar: the XP label is dropped)
L.XP_LABEL                = "XP:"  -- themes with split texts: label before the XP numbers (XP_BARE_FMT)
L.LEVEL_TITLE_FMT         = "Livello %d"  -- [fmt] level (themes with title-case level texts)
L.LEVEL_CAP_TAG           = "LIMITE"  -- themes: detected server level cap, after the level (upper case)
L.LEVEL_CAP_TAG_TITLE     = "Limite"  -- themes: detected server level cap, after LEVEL_TITLE_FMT
L.UNLOCKED_HINT           = "Trascina per spostare · Clic destro: menu"
L.MAX_LEVEL               = "Livello massimo"

-- Tooltip
L.TT_LEVEL_FMT            = "Livello %d » %d"  -- [fmt] level, next level
L.TT_XP                   = "XP"
L.TT_REMAINING            = "Mancanti"
L.TT_RESTED               = "Riposato"
L.TT_RESTED_FMT           = "%s XP (%s)"  -- [fmt] number, percent of the level
L.TT_NEXT_LEVEL           = "Prossimo livello"
L.TT_XPH                  = "XP all'ora"
L.TT_KILLS                = "Mostri da uccidere"
L.TT_KILLS_FMT            = "~%s (media: %s XP, ultimo: %s XP)"  -- [fmt] count, average XP of the last 10 kills, XP of the last kill (both without rested bonus)
L.TT_KILLS_NODATA         = "dopo la tua prossima uccisione"
L.TT_RATES_FMT            = "sessione %s · livello %s"  -- [fmt] rates
L.TT_WARMING_FMT          = "stima tra ~%s"  -- [fmt] duration
L.TT_NO_RATE              = "dati ancora insufficienti"
L.TT_NODATA_FMT           = "disponibile dopo ~%s di gioco contato"  -- [fmt] duration
L.TT_NODATA_XP            = "disponibile dopo il tuo primo guadagno di XP"
L.RATE_ESTIMATE           = "stima dal tuo /played"
L.TT_SRC_LEVEL            = "in base a questo livello"
L.TT_SRC_RECENT           = "in base agli ultimi livelli"
L.TT_PAUSED_FMT           = "Cronometro in pausa: %s escluso"  -- [fmt] PAUSE_*
L.PAUSE_AFK               = "tempo AFK"
L.PAUSE_INN               = "tempo in locanda"
L.PAUSE_CITY              = "tempo in città"
L.MASK_AFK                = "AFK"
L.MASK_INN                = "locanda"
L.MASK_CITY               = "città"
L.TT_READONLY             = "Sola lettura: dati di una versione più recente"
L.TT_EXCL_FMT             = "escl. %s"  -- [fmt] mask label
L.TT_SESSION              = "Sessione"
L.TT_THIS_LEVEL           = "Questo livello"
L.TT_ZONE_FMT             = "Zona: %s"  -- [fmt] zone name
L.TT_PLAYED               = "Giocato"
L.TT_PLAYED_EXCL_FMT      = "Giocato (escl. %s)"  -- [fmt] mask label
L.TT_PREINSTALL_FMT       = "incl. %s prima dell'installazione, non filtrato"  -- [fmt] duration
L.TT_EST_FMT              = "incl. %s ricostruito dopo un crash"  -- [fmt] duration
L.TT_SERVER               = "/played del server"
L.TT_SERVER_AGE_FMT       = "%s (%s)"  -- [fmt] duration, AGO text
L.TT_AVG_LEVEL            = "Media per livello"
L.TT_AVG_RECENT_FMT       = "Media degli ultimi %d livelli"  -- [fmt] count (always >= 2)
L.TT_BREAKDOWN            = "Ripartizione"
L.BD_PART_FMT             = "%s %s"  -- [fmt] part label (BD_*), percent
L.BD_WORLD                = "Mondo"
L.BD_DUNGEON              = "Spedizioni"
L.BD_RAID                 = "Incursioni"
L.BD_PVP                  = "PvP"
L.BD_TAXI                 = "Volo"
L.BD_AFK                  = "AFK"
L.BD_INN                  = "Locanda"
L.BD_CITY                 = "Città"
L.TT_INSTANCES            = "In istanza"
L.TT_HINT                 = "Maiusc: dettagli · Clic: statistiche · Clic destro: menu"
L.TT_HINT_COMPARTMENT     = "Maiusc: dettagli · Clic: opzioni · Clic destro: statistiche"
L.TT_MAX_LEVEL            = "Livello massimo raggiunto"
L.TT_CAP_FMT              = "Livello %d: limite di livello attuale del server (nessun XP dagli ultimi %d mostri)"  -- [fmt] level, mobs killed without XP (3 or more)
L.TT_CAP_RESUME           = "Il conteggio degli XP riprende da solo appena il server torna a dare XP."
L.TT_STALLED_FMT          = "%s XP all'ora congelati: nessun XP da %s di gioco"  -- [fmt] STALL_MARK, duration of counted play
L.TT_STALLED_RESUME       = "Riprende al tuo prossimo guadagno di XP; il tempo senza XP non viene contato."
L.TT_TOP_ZONES            = "Zone principali del livello"
L.TT_TOP_CITIES           = "Capitali più frequentate"
L.SECTION_CONTINENTS      = "Continenti"
L.CONT_INSTANCES          = "Istanze"
L.CONT_OTHER              = "Altro"
L.TT_OF_WHICH_AFK_FMT     = "%s (di cui AFK %s)"  -- [fmt] durations
L.TT_LAST_LEVELS          = "Ultimi livelli"
L.TT_LEVEL_ROW_FMT        = "Livello %d"  -- [fmt] level
L.TT_INN                  = "Locanda / zona di riposo"
L.TT_CITY                 = "Città"
L.TT_AFK                  = "AFK"
L.TT_TAXI                 = "Volo"
L.TT_DEATHS               = "Morti"
L.TT_UNTRACKED            = "Prima dell'installazione / non tracciato"
L.TT_UNTRACKED_NOTE       = "non ripartito"
L.TT_EST_TOTAL            = "Ricostruito dopo i crash"
L.TT_EST_NOTE             = "ripartizione stimata"
L.TT_ACCOUNT_FMT          = "Account (%d personaggi)"  -- [fmt] count (2 or more)
L.TT_ACCOUNT_ONE_FMT      = "Account (%d personaggio)"  -- [fmt] count (1)
L.TT_ACCOUNT_INST         = "Account, in istanza"
L.TT_NET                  = "FPS · locale · mondo"
L.TT_NET_FMT              = "%s · %s · %s"  -- [fmt] fps, home, world

-- Context menu
L.MENU_EXCLUDE_AFK        = "Escludi il tempo AFK"
L.MENU_EXCLUDE_INN        = "Escludi il tempo in locanda / zona di riposo"
L.MENU_EXCLUDE_CITY       = "Escludi il tempo in città"
L.MENU_LOCK               = "Blocca"
L.MENU_THEME              = "Tema"
L.MENU_STATS              = "Statistiche..."
L.MENU_RESET_SESSION      = "Reimposta sessione"
L.MENU_HIDE               = "Nascondi"
L.MENU_OPTIONS            = "Opzioni..."

-- Options panel
L.OPT_EXCLUSIONS          = "Esclusioni"
L.OPT_EXCLUSIONS_HELP     = "Le esclusioni cambiano solo ciò che vedi: non viene cancellato nulla e tutto viene ricalcolato subito."
L.OPT_CITY_HELP           = "Città: Roccavento, Forgiardente, Darnassus, Orgrimmar, Picco del Tuono, Sepulcria (/tpl citytoggle aggiunge o rimuove la zona attuale). Locanda / zona di riposo: qualsiasi altra zona di riposo."
L.OPT_DISPLAY             = "Visualizzazione"
L.OPT_THEME               = "Tema"
L.OPT_THEME_NOTE          = "Cambia l'aspetto della barra, del suo tooltip, del grafico e della finestra delle statistiche. I colori che scegli qui sotto sostituiscono quelli del tema."
L.OPT_THEME_RESTART_NOTE  = "Dopo aver installato o aggiornato TruePlayed, riavvia il gioco (un /reload non basta) perché si carichino i caratteri e le texture dei temi."
L.OPT_SHOW                = "Mostra la barra"
L.OPT_SLOT1               = "Info 1 (grande)"
L.OPT_SLOT2               = "Info 2"
L.OPT_SLOT3               = "Info 3"
L.OPT_SLOT3_POS           = "Posizione dell'info 3"
L.OPT_SLOTS_NOTE          = "Info 1 in alto a destra, info 2 dopo gli XP, info 3 in alto."
L.POS_CENTER              = "In alto al centro"
L.POS_LEFT                = "In alto a sinistra"
L.OPT_PCT_POS             = "Percentuale del livello"
L.PCT_FOLLOW              = "Segue la barra"
L.PCT_LEVEL               = "Accanto al livello"
L.OPT_MAX_SLOTS           = "Al livello massimo, sostituisci le info sugli XP con:"
L.OPT_MAX_SLOT_FMT        = "Info %d al livello massimo"  -- [fmt] slot index
L.OPT_WIDTH               = "Larghezza"
L.OPT_HEIGHT              = "Altezza della barra"
L.OPT_SCALE               = "Scala"
L.OPT_FONT_SIZE           = "Dimensione del testo"
L.OPT_LOCK                = "Blocca la posizione"
L.OPT_COMBAT_HIDE         = "Nascondi in combattimento"
L.OPT_FADE                = "Sfuma quando il mouse è lontano"
L.OPT_HIDE_MAX            = "Nascondi al livello massimo"
L.OPT_LANGUAGE            = "Lingua (Language)"
L.OPT_LANGUAGE_NOTE       = "La lingua di TruePlayed cambia dopo aver ricaricato l'interfaccia (pulsante qui sotto o /reload). I nomi forniti dal gioco (zone, mostri, istanze, personaggi) restano nella lingua del client di gioco."
L.OPT_RELOAD              = "Ricarica interfaccia"
L.LANG_AUTO               = "Auto"
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
L.OPT_TEXTS               = "Testi"
L.OPT_TEXT_COLOR          = "Colore del testo"
L.OPT_TEXT_COLOR_RESET    = "Colori del tema"
L.OPT_TEXT_COLOR_NOTE     = "Vale per tutti i testi della barra. I colori della barra stessa si impostano più in basso."
L.OPT_OUTLINE             = "Contorno del testo"
L.OUTLINE_NONE            = "Nessuno"
L.OUTLINE_THIN            = "Sottile"
L.OUTLINE_THICK           = "Spesso"
L.OPT_SHADOW              = "Ombra del testo"
L.OPT_BG_ALPHA            = "Opacità dello sfondo"
L.OPT_BAR_COLORS          = "Colori della barra"
L.OPT_XP_COLOR            = "Colore della barra XP"
L.OPT_RESTED_COLOR        = "Colore degli XP riposo"
L.OPT_BAR_COLORS_RESET    = "Colori del tema"
L.OPT_BAR_COLORS_NOTE     = "Finché non scegli i tuoi, la barra usa i colori del tema. Quando sei riposato, la barra prende il colore degli XP riposo, e una tonalità più chiara mostra fin dove arrivano i tuoi XP riposo. Al livello massimo la barra è piena, nel colore della barra XP, attenuata."
L.OPT_NET                 = "FPS e latenza"
L.OPT_QUALITY_COLORS      = "Colori di qualità (verde, giallo, rosso)"
L.OPT_QUALITY_COLORS_NOTE = "Senza spunta, FPS e latenza usano il colore del testo."
L.OPT_GRAPH_WINDOW        = "Durata del grafico"
L.OPT_GRAPH_NOTE          = "Passa il mouse su FPS o latenza nella barra per vederne il grafico, poi sul grafico per leggere un valore. Il gioco aggiorna la latenza solo ogni 30 secondi circa."
L.OPT_CALC                = "Calcolo"
L.OPT_REACTIVITY          = "Reattività degli XP all'ora"
L.OPT_REACTIVITY_HELP     = "Quanto in fretta gli XP all'ora seguono il tuo ritmo recente."
L.REACT_SLOW              = "Lenta (90 min)"
L.REACT_NORMAL            = "Normale (60 min)"
L.REACT_FAST              = "Rapida (20 min)"
L.OPT_REQUEST_PLAYED      = "Chiedi il /played al server all'accesso"
L.OPT_REQUEST_PLAYED_HELP = "Necessario per recuperare il tempo dopo un crash. Le solite righe del /played compaiono una volta in chat, solo se nessun altro addon l'ha chiesto entro 10 secondi."
L.OPT_HIDE_PLAYED         = "Nascondi le righe del /played quando lo chiede TruePlayed (sperimentale)"
L.OPT_HIDE_PLAYED_HELP    = "Intercetta per poco la visualizzazione del /played in chat mentre la richiesta di TruePlayed è in corso. Un /played digitato da te viene sempre mostrato. Può disturbare la chat nelle spedizioni: disattivalo se vedi errori in chat."
L.OPT_HIDE_PLAYED_NA      = "Non disponibile su questo client."
L.OPT_CITIES              = "Città"
L.OPT_CITY_CURRENT_FMT    = "Zona attuale: %s (%s)"  -- [fmt] zone name, CITY_YES/CITY_NO
L.CITY_YES                = "contata come città"
L.CITY_NO                 = "non è una città"
L.OPT_CITY_TOGGLE         = "Conta / non contare questa zona come città"
L.OPT_DATA                = "Dati"
L.OPT_OPEN_STATS          = "Statistiche..."
L.OPT_RESET_POS           = "Reimposta posizione"
L.OPT_RESET_SESSION       = "Reimposta sessione"
L.OPT_RESET_RATE          = "Reimposta XP/h"
L.OPT_RESET_CHAR          = "Cancella i dati di questo personaggio"
L.CONFIRM_ERASE_CHAR_FMT  = "Cancellare tutti i dati di TruePlayed di %s? Non si può annullare."  -- [fmt] name
L.ERASE_YES               = "Sì"  -- the erase popup's buttons (the game's YES / NO follow the client)
L.ERASE_NO                = "No"
L.OPT_NOTE_PREINSTALL     = "Il tempo giocato prima di installare TruePlayed non può essere ripartito e non viene mai escluso."
L.OPT_NOTE_IDLE           = "I pochi minuti prima che il gioco ti segni AFK in automatico contano ancora come attivi."
L.OPT_NOTE_CRASH          = "Dopo un crash del gioco (o se giochi senza TruePlayed), il tempo mancante viene ripreso dal /played del server e ripartito secondo le tue abitudini; viene segnato come ricostruito."
L.OPT_NOTE_CITY           = "Il tempo in città si conta per mappa: tutta la capitale conta come città, non solo la sua locanda."
L.OPT_NOTE_STALL_FMT      = "Dopo %d minuti di gioco senza XP (un limite di livello, una lunga pausa in città...), gli XP all'ora e il tempo al prossimo livello si congelano: quel tempo non viene contato, e ripartono al tuo prossimo guadagno di XP."  -- [fmt] minutes
L.OPT_NOTE_CAP_FMT        = "Un server con un limite di livello temporaneo (beta) viene riconosciuto quando %d mostri di fila non danno XP: la barra appare allora come al livello massimo, e torna normale da sola appena gli XP ritornano."  -- [fmt] mobs
L.OPT_NOTE_READONLY       = "Sola lettura: i tuoi dati sono stati salvati da una versione più recente di TruePlayed. Aggiorna l'addon; nel frattempo non viene registrato nulla."
L.OPT_VERSION_FMT         = "Versione %s"  -- [fmt] version
L.SLIDER_PX_FMT           = "%d px"  -- [fmt] value
L.SLIDER_PCT_FMT          = "%d%%"  -- [fmt] value

-- Themes (display names: options dropdown, context menu, /tpl theme)
L.THEME_FUTURISTE         = "Futuristico"
L.THEME_ACTUEL            = "Classico"
L.THEME_HEROIC            = "Fantasy eroico"
L.THEME_PIXEL             = "Pixel (retrò)"
L.THEME_CLASS             = "Classe (automatico)"
L.THEME_WARRIOR           = "Guerriero"
L.THEME_PALADIN           = "Paladino"
L.THEME_HUNTER            = "Cacciatore"
L.THEME_ROGUE             = "Ladro"
L.THEME_PRIEST            = "Sacerdote"
L.THEME_SHAMAN            = "Sciamano"
L.THEME_MAGE              = "Mago"
L.THEME_WARLOCK           = "Stregone"
L.THEME_DRUID             = "Druido"

-- Statistics window
L.WIN_TITLE               = "TruePlayed - statistiche"
L.VIEW_ACCOUNT            = "Account (tutti i personaggi)"
L.WIN_ERASE               = "Cancella..."
L.WIN_FILTER_FMT          = "Tempi mostrati escl. %s"  -- [fmt] mask label
L.TAB_LEVELS              = "Livelli"
L.TAB_ZONES               = "Zone"
L.TAB_SESSIONS            = "Sessioni"
L.COL_LEVEL               = "Liv."
L.COL_TIME                = "Tempo"
L.COL_SERVER              = "Server"
L.COL_XPH                 = "XP/h"
L.COL_AFK                 = "AFK"
L.COL_INN                 = "Locanda"
L.COL_CITY                = "Città"
L.COL_INST                = "Ist."
L.COL_MAIN_ZONE           = "Zona principale"
L.COL_REACHED             = "Raggiunto"
L.COL_ZONE                = "Zona"
L.COL_RAW                 = "Grezzo"
L.COL_XP                  = "XP"
L.COL_DATE                = "Data"
L.COL_DURATION            = "Durata"
L.COL_LEVELS              = "Livelli"
L.COL_DEATHS              = "Morti"
L.COL_CHARS               = "Pers."
L.COL_AVG                 = "Media"
L.ROW_IN_PROGRESS         = "in corso"
L.ROW_PARTIAL_TIP         = "Livello iniziato prima di installare TruePlayed."
L.ROW_REC_TIP             = "Raggiunto durante un crash o senza TruePlayed: tempo stimato dal /played del server e dai tuoi XP."
L.ROW_EST_TIP_FMT         = "Include %s ricostruito dopo un crash (ripartizione stimata)."  -- [fmt] duration
L.ROW_GAP_TIP_FMT         = "Il tempo del server supera di %s quello tracciato (non ripartito)."  -- [fmt] duration
L.ROW_ZONES_FMT           = "Zone al livello %d"  -- [fmt] level
L.ROW_ZONES_EMPTY         = "Nessuna zona registrata per questo livello."
L.LEVELS_HOVER_HINT       = "Passa il mouse su un livello per vederne le zone."
L.FOOTER_FMT              = "Media per livello: %s · ultimi %d livelli: %s · totale: %s"  -- [fmt] dur, count, dur, dur
L.FOOTER_ACCOUNT_FMT      = "Media per livello dell'account: %s (%d personaggi)"  -- [fmt] dur, count (2 or more)
L.FOOTER_ACCOUNT_ONE_FMT  = "Media per livello dell'account: %s (%d personaggio)"  -- [fmt] dur, count (1)
L.FOOTER_ACCOUNT_NONE     = "Media per livello dell'account: dati ancora insufficienti"
L.CITIES_HEADER           = "Capitali più frequentate"
L.INSTANCES_HEADER        = "Istanze più giocate"
L.INST_ROW_FMT            = "%s (%s)"  -- [fmt] instance name, KIND_*
L.KIND_DUNGEON            = "spedizione"
L.KIND_RAID               = "incursione"
L.KIND_PVP                = "PvP"
L.FOOTER_INST_FMT         = "in istanza: %s"  -- [fmt] duration
L.NO_DATA                 = "Ancora nessun dato."
L.NO_SESSIONS_ACCOUNT     = "Le sessioni sono elencate per personaggio."
L.CITY_MARK               = "(città)"
L.CHAR_FMT                = "%s - livello %d"  -- [fmt] name, level
L.ZONE_UNKNOWN            = "Zona sconosciuta"
L.ZONE_OTHER              = "Altre zone"

-- FPS / latency graph (Graph.lua)
L.GRAPH_TITLE_FMT         = "FPS e latenza su %s"  -- [fmt] GRAPH_WINDOW_*
L.GRAPH_WINDOW_30         = "30 s"
L.GRAPH_WINDOW_60         = "1 min"
L.GRAPH_WINDOW_300        = "5 min"
L.GRAPH_AGO_FMT           = "%s fa: %s · %s"  -- [fmt] age (GRAPH_AGE_*), FPS text, latency text
L.GRAPH_AGE_S_FMT         = "%d s"  -- [fmt] seconds (age below one minute)
L.GRAPH_AGE_MS_FMT        = "%d min %02d s"  -- [fmt] minutes, seconds
L.GRAPH_MIN_AVG_MAX_FMT   = "min %s · media %s · max %s"  -- [fmt] values
L.GRAPH_LAT_NOTE          = "Il gioco aggiorna la latenza solo ogni 30 s circa: è disegnata a gradini."
L.GRAPH_NO_DATA           = "Raccolta dei campioni..."

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
