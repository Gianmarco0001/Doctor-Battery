// i18n translations for Doctor Battery
window.__I18N__ = {
  en: {
    nav: { features: "Features", preview: "Preview", download: "Download", source: "GitHub" },
    hero: {
      badge: "v1.4 — universal binary, signed",
      title: ["Free", "battery", "diagnostics", "for Mac,", "iPhone", "&", "iPad."],
      sub: "Open-source. No telemetry. Every byte stays on your Mac.",
      cta1: "Download for macOS",
      cta2: "View on GitHub",
      meta: "Universal binary · Apple Silicon + Intel · macOS 13+"
    },
    dash: {
      devices: "Devices",
      cycles: "cycles",
      health: "Health",
      cyclesLabel: "Cycles",
      remaining: "713 left · ~3.8y",
      temp: "Temperature",
      tempTrend: "Optimal range",
      forecastTitle: "Health forecast",
      forecastLegend: "12 mo · linear regression"
    },
    preview: {
      eyebrow: "/* preview */",
      title: "What it looks like.",
      sub: "Three views, one app. Everything you need, nothing else.",
      cap1: "Mac · cycles, raw FCC health, real-time wattage, adapter quality, history chart.",
      cap2: "iPhone & iPad · over USB or Wi-Fi via libimobiledevice.",
      cap3: "Settings · launch at login, log interval, language, thresholds.",
      ssMac: "Mac", ssIphone: "iPhone", ssIpad: "iPad",
      ssCycles: "Cycles", ssHealth: "Health (FCC)", ssCap: "Capacity",
      ssVolt: "Voltage", ssTemp: "Temperature", ssAdapter: "Adapter",
      ssModel: "Model", ssDesignCap: "Design cap", ssRealCap: "Real cap", ssConn: "Connection",
      ssSettings: "Settings", ssLogin: "Launch at login", ssNotif: "Anomaly alerts",
      ssLang: "Language", ssLangVal: "English", ssInterval: "Log interval", ssThreshold: "Alert threshold"
    },
    show: {
      e1: "01 — Real numbers", t1: ["The same number", "your Mac sees."],
      b1: "We read the gas-gauge IC directly — the same FCC value your system uses internally. No marketing, no rounding, no curated estimate. Just raw truth, exposed transparently.",
      e2: "02 — Forecast", t2: ["Know when", "before it knows."],
      b2: "Linear regression across your full history projects exactly when your battery will reach 80% — and how many cycles you have left before service is recommended.",
      e3: "03 — Every device", t3: ["Mac, iPhone, iPad.", "One window."],
      b3: "Pair once over USB, monitor over Wi-Fi forever. Cycle count, capacity, temperature and voltage for the whole family — without ever leaving your desk.",
      forecastNote: "80% in ~14 mo", liveDevices: "3 devices · live"
    },
    feat: {
      eyebrow: "/* features */",
      title: ["Everything you need to know", "about your batteries."],
      sub: "Eight modules, one app, zero analytics. Diagnostics as it should be — pure information.",
      f1t: "Raw FCC health", f1b: "Reads the gas-gauge IC directly. Same numbers your system uses internally — exposed transparently.",
      f2t: "Cycle counting & forecast", f2b: "Linear-regression forecast tells you when health will hit 80% and how many cycles you have left.",
      f3t: "iPhone & iPad support", f3b: "Full battery details over USB or Wi-Fi via libimobiledevice. Cycle count, capacity, temperature, voltage.",
      f4t: "Power adapter classifier", f4b: "Identifies original, MFi-certified or generic chargers from the FamilyCode IORegistry value.",
      f5t: "History & charts", f5b: "SQLite-backed history with overlapping charts across all your devices. CSV export.",
      f6t: "Smart notifications", f6b: "Anomaly detection: alerts you if health drops faster than normal. Plus low battery, hot battery, calibration reminders.",
      f7t: "Localized", f7b: "English, Italian, French, Spanish and German out of the box. More languages welcome via PR.",
      f8t: "Privacy first", f8b: "No analytics, no network calls, no account. Data sits in ~/Library/Application Support/BatteryMonitor.",
      f9t: "Live readings", f9b: "Updates every second while connected. Watch voltage and temperature respond to load in real time."
    },
    dl: {
      eyebrow: "/* download */",
      title: "One click to install.",
      sub: "Pre-built universal binary on GitHub Releases.",
      btn: "Latest release · v1.4.0",
      meta: "macOS 13+ · ~6.4 MB · SHA256 verified",
      i1t: "First launch", i1b: "The app is signed ad-hoc, so Gatekeeper warns on first launch. Right-click the .app → Open → confirm. macOS remembers the choice.",
      i2t: "iOS / iPadOS support", i2b: "Install libimobiledevice, then connect & trust your device once."
    },
    build: {
      eyebrow: "/* build */",
      title: "Build from source.",
      sub: "Pure Swift + SwiftUI + Swift Charts. No third-party dependencies. ~1300 LOC.",
      meta: "MIT License · Made with care for batteries everywhere."
    },
    contact: {
      eyebrow: "/* contact */",
      title: "Get in touch.",
      sub: "Found a bug, want a feature, or just want to say hi?",
      email: "Email", donate: "Donate", donateSub: "Support development"
    },
    footer: "Not affiliated with any device manufacturer · MIT License · Built with ♥ for transparency."
  },

  it: {
    nav: { features: "Funzioni", preview: "Anteprima", download: "Download", source: "GitHub" },
    hero: {
      badge: "v1.4 — universal binary, firmato",
      title: ["Diagnostica", "batteria", "gratuita", "per Mac,", "iPhone", "e", "iPad."],
      sub: "Open source. Nessuna telemetria. Tutto resta sul tuo Mac.",
      cta1: "Scarica per macOS",
      cta2: "Vedi su GitHub",
      meta: "Universal binary · Apple Silicon + Intel · macOS 13+"
    },
    dash: {
      devices: "Dispositivi",
      cycles: "cicli",
      health: "Salute",
      cyclesLabel: "Cicli",
      remaining: "713 rimasti · ~3,8 anni",
      temp: "Temperatura",
      tempTrend: "Range ottimale",
      forecastTitle: "Previsione salute",
      forecastLegend: "12 mesi · regressione lineare"
    },
    preview: {
      eyebrow: "/* anteprima */",
      title: "Come si presenta.",
      sub: "Tre viste, un'app. Tutto quello che ti serve, nessuna distrazione.",
      cap1: "Mac · cicli, salute raw FCC, wattaggio in tempo reale, qualità alimentatore, grafico storico.",
      cap2: "iPhone e iPad · via USB o Wi-Fi con libimobiledevice.",
      cap3: "Impostazioni · avvio al login, intervallo log, lingua, soglie.",
      ssMac: "Mac", ssIphone: "iPhone", ssIpad: "iPad",
      ssCycles: "Cicli", ssHealth: "Salute (FCC)", ssCap: "Capacità",
      ssVolt: "Voltaggio", ssTemp: "Temperatura", ssAdapter: "Alimentatore",
      ssModel: "Modello", ssDesignCap: "Cap. design", ssRealCap: "Cap. reale", ssConn: "Connessione",
      ssSettings: "Impostazioni", ssLogin: "Avvio al login", ssNotif: "Notifiche anomalie",
      ssLang: "Lingua", ssLangVal: "Italiano", ssInterval: "Intervallo log", ssThreshold: "Soglia avviso"
    },
    show: {
      e1: "01 — Numeri reali", t1: ["Lo stesso numero", "che vede il tuo Mac."],
      b1: "Leggiamo direttamente il chip gas-gauge — lo stesso valore FCC che il sistema usa internamente. Niente marketing, niente arrotondamenti, niente stime addolcite. Solo verità grezza, esposta in chiaro.",
      e2: "02 — Previsione", t2: ["Sappi quando", "prima del tempo."],
      b2: "La regressione lineare sull'intero storico proietta esattamente quando la batteria scenderà all'80% — e quanti cicli ti restano prima dell'assistenza.",
      e3: "03 — Ogni dispositivo", t3: ["Mac, iPhone, iPad.", "Una sola finestra."],
      b3: "Accoppia una volta via USB, monitora per sempre via Wi-Fi. Cicli, capacità, temperatura e voltaggio per tutta la famiglia — senza mai alzarti dalla scrivania.",
      forecastNote: "80% in ~14 mesi", liveDevices: "3 dispositivi · live"
    },
    feat: {
      eyebrow: "/* funzioni */",
      title: ["Tutto quello che serve sapere", "sulle tue batterie."],
      sub: "Otto moduli, una sola app, zero analytics. La diagnostica che dovrebbe essere — informazione pura.",
      f1t: "Salute raw FCC", f1b: "Legge direttamente il chip gas-gauge. Stessi numeri usati internamente dal sistema — esposti in modo trasparente.",
      f2t: "Cicli e previsione", f2b: "La regressione lineare ti dice quando la salute scenderà all'80% e quanti cicli ti restano.",
      f3t: "Supporto iPhone e iPad", f3b: "Dettagli completi via USB o Wi-Fi tramite libimobiledevice. Cicli, capacità, temperatura, voltaggio.",
      f4t: "Classificatore alimentatori", f4b: "Identifica caricatori originali, MFi-certificati o generici dal valore FamilyCode in IORegistry.",
      f5t: "Storico e grafici", f5b: "Storico SQLite con grafici sovrapposti per tutti i dispositivi. Esportazione CSV.",
      f6t: "Notifiche intelligenti", f6b: "Anomalie rilevate: avviso se la salute cala più del normale. Plus batteria scarica, surriscaldata, promemoria calibrazione.",
      f7t: "Localizzata", f7b: "Inglese, italiano, francese, spagnolo e tedesco di serie. Altre lingue benvenute via PR.",
      f8t: "Privacy first", f8b: "Nessuna analytics, nessuna chiamata di rete, nessun account. Dati in ~/Library/Application Support/BatteryMonitor.",
      f9t: "Letture in tempo reale", f9b: "Aggiornamento ogni secondo finché il dispositivo è connesso. Vedi voltaggio e temperatura rispondere al carico."
    },
    dl: {
      eyebrow: "/* download */",
      title: "Un click e sei a posto.",
      sub: "Universal binary pre-compilato su GitHub Releases.",
      btn: "Ultima release · v1.4.0",
      meta: "macOS 13+ · ~6.4 MB · SHA256 verificato",
      i1t: "Primo avvio", i1b: "L'app è firmata ad-hoc, quindi Gatekeeper avvisa al primo avvio. Click destro sull'.app → Apri → conferma. macOS ricorderà la scelta.",
      i2t: "Supporto iOS / iPadOS", i2b: "Installa libimobiledevice, poi connetti e autorizza il dispositivo."
    },
    build: {
      eyebrow: "/* build */",
      title: "Compila dal sorgente.",
      sub: "Pure Swift + SwiftUI + Swift Charts. Nessuna dipendenza esterna. ~1300 LOC.",
      meta: "Licenza MIT · Fatto con cura per le batterie di tutti."
    },
    contact: {
      eyebrow: "/* contatti */",
      title: "Mettiamoci in contatto.",
      sub: "Bug, richiesta di feature, o solo un saluto?",
      email: "Email", donate: "Donazione", donateSub: "Supporta lo sviluppo"
    },
    footer: "Non affiliato a nessun produttore di dispositivi · Licenza MIT · Costruito con ♥ per la trasparenza."
  },

  fr: {
    nav: { features: "Fonctions", preview: "Aperçu", download: "Téléchargement", source: "GitHub" },
    hero: {
      badge: "v1.4 — universal binary, signé",
      title: ["Diagnostic", "de batterie", "gratuit", "pour Mac,", "iPhone", "et", "iPad."],
      sub: "Open source. Aucune télémétrie. Tout reste sur votre Mac.",
      cta1: "Télécharger pour macOS",
      cta2: "Voir sur GitHub",
      meta: "Universal binary · Apple Silicon + Intel · macOS 13+"
    },
    dash: {
      devices: "Appareils", cycles: "cycles", health: "Santé", cyclesLabel: "Cycles",
      remaining: "713 restants · ~3,8 ans", temp: "Température", tempTrend: "Plage optimale",
      forecastTitle: "Prévision santé", forecastLegend: "12 mois · régression linéaire"
    },
    preview: {
      eyebrow: "/* aperçu */",
      title: "À quoi ça ressemble.",
      sub: "Trois vues, une app. Tout ce dont vous avez besoin, rien d'autre.",
      cap1: "Mac · cycles, santé FCC brute, puissance en temps réel, qualité d'adaptateur, graphique d'historique.",
      cap2: "iPhone et iPad · via USB ou Wi-Fi avec libimobiledevice.",
      cap3: "Réglages · démarrage au login, intervalle de log, langue, seuils.",
      ssMac: "Mac", ssIphone: "iPhone", ssIpad: "iPad",
      ssCycles: "Cycles", ssHealth: "Santé (FCC)", ssCap: "Capacité",
      ssVolt: "Tension", ssTemp: "Température", ssAdapter: "Adaptateur",
      ssModel: "Modèle", ssDesignCap: "Cap. design", ssRealCap: "Cap. réelle", ssConn: "Connexion",
      ssSettings: "Réglages", ssLogin: "Au démarrage", ssNotif: "Alertes anomalies",
      ssLang: "Langue", ssLangVal: "Français", ssInterval: "Intervalle", ssThreshold: "Seuil d'alerte"
    },
    show: {
      e1: "01 — Vrais chiffres", t1: ["Le même chiffre", "que voit votre Mac."],
      b1: "Nous lisons directement le chip gas-gauge — la même valeur FCC que le système utilise en interne. Pas de marketing, pas d'arrondi, pas d'estimation édulcorée. Juste la vérité brute, exposée clairement.",
      e2: "02 — Prévision", t2: ["Sachez quand", "avant l'heure."],
      b2: "La régression linéaire sur tout l'historique projette exactement quand la batterie atteindra 80% — et combien de cycles il vous reste avant le service.",
      e3: "03 — Chaque appareil", t3: ["Mac, iPhone, iPad.", "Une fenêtre."],
      b3: "Appairez une fois via USB, surveillez à jamais en Wi-Fi. Cycles, capacité, température et tension pour toute la famille — sans quitter votre bureau.",
      forecastNote: "80% dans ~14 mois", liveDevices: "3 appareils · live"
    },
    feat: {
      eyebrow: "/* fonctions */",
      title: ["Tout ce qu'il faut savoir", "sur vos batteries."],
      sub: "Huit modules, une app, zéro analytics. Le diagnostic comme il devrait être — information pure.",
      f1t: "Santé FCC brute", f1b: "Lit directement le chip gas-gauge. Mêmes chiffres utilisés en interne — exposés en toute transparence.",
      f2t: "Comptage et prévision", f2b: "La régression linéaire vous dit quand la santé atteindra 80% et combien de cycles il reste.",
      f3t: "Support iPhone et iPad", f3b: "Détails complets via USB ou Wi-Fi avec libimobiledevice. Cycles, capacité, température, tension.",
      f4t: "Classificateur d'adaptateurs", f4b: "Identifie chargeurs originaux, MFi-certifiés ou génériques via la valeur FamilyCode IORegistry.",
      f5t: "Historique et graphiques", f5b: "Historique SQLite avec graphiques superposés pour tous les appareils. Export CSV.",
      f6t: "Notifications intelligentes", f6b: "Détection d'anomalies : alerte si la santé chute plus vite que la normale. Plus batterie faible, chaude, rappel calibrage.",
      f7t: "Localisée", f7b: "Anglais, italien, français, espagnol et allemand par défaut. Autres langues bienvenues via PR.",
      f8t: "Privacy first", f8b: "Aucune analytics, aucun appel réseau, aucun compte. Données dans ~/Library/Application Support/BatteryMonitor.",
      f9t: "Lectures en direct", f9b: "Mise à jour chaque seconde tant que l'appareil est connecté. Voyez tension et température réagir à la charge."
    },
    dl: {
      eyebrow: "/* download */",
      title: "Un clic et c'est installé.",
      sub: "Universal binary pré-compilé sur GitHub Releases.",
      btn: "Dernière release · v1.4.0",
      meta: "macOS 13+ · ~6.4 Mo · SHA256 vérifié",
      i1t: "Premier lancement", i1b: "L'app est signée ad-hoc, donc Gatekeeper avertit au premier lancement. Clic droit sur l'.app → Ouvrir → confirmer. macOS retient le choix.",
      i2t: "Support iOS / iPadOS", i2b: "Installez libimobiledevice, puis connectez et autorisez l'appareil."
    },
    build: {
      eyebrow: "/* build */",
      title: "Compiler depuis les sources.",
      sub: "Pure Swift + SwiftUI + Swift Charts. Aucune dépendance externe. ~1300 LOC.",
      meta: "Licence MIT · Fait avec soin pour toutes les batteries."
    },
    contact: {
      eyebrow: "/* contact */",
      title: "Contactez-moi.",
      sub: "Un bug, une demande de fonctionnalité ou juste un bonjour ?",
      email: "Email", donate: "Faire un don", donateSub: "Soutenir le développement"
    },
    footer: "Non affilié à un fabricant · Licence MIT · Construit avec ♥ pour la transparence."
  },

  es: {
    nav: { features: "Funciones", preview: "Vista", download: "Descargas", source: "GitHub" },
    hero: {
      badge: "v1.4 — universal binary, firmado",
      title: ["Diagnóstico", "de batería", "gratis", "para Mac,", "iPhone", "y", "iPad."],
      sub: "Código abierto. Sin telemetría. Todo se queda en tu Mac.",
      cta1: "Descargar para macOS",
      cta2: "Ver en GitHub",
      meta: "Universal binary · Apple Silicon + Intel · macOS 13+"
    },
    dash: {
      devices: "Dispositivos", cycles: "ciclos", health: "Salud", cyclesLabel: "Ciclos",
      remaining: "713 restantes · ~3,8 años", temp: "Temperatura", tempTrend: "Rango óptimo",
      forecastTitle: "Pronóstico de salud", forecastLegend: "12 meses · regresión lineal"
    },
    preview: {
      eyebrow: "/* vista */",
      title: "Cómo se ve.",
      sub: "Tres vistas, una app. Todo lo que necesitas, nada más.",
      cap1: "Mac · ciclos, salud FCC cruda, vatiaje en tiempo real, calidad del adaptador, gráfico histórico.",
      cap2: "iPhone y iPad · vía USB o Wi-Fi con libimobiledevice.",
      cap3: "Ajustes · inicio al login, intervalo de log, idioma, umbrales.",
      ssMac: "Mac", ssIphone: "iPhone", ssIpad: "iPad",
      ssCycles: "Ciclos", ssHealth: "Salud (FCC)", ssCap: "Capacidad",
      ssVolt: "Voltaje", ssTemp: "Temperatura", ssAdapter: "Adaptador",
      ssModel: "Modelo", ssDesignCap: "Cap. diseño", ssRealCap: "Cap. real", ssConn: "Conexión",
      ssSettings: "Ajustes", ssLogin: "Iniciar al login", ssNotif: "Alertas anomalías",
      ssLang: "Idioma", ssLangVal: "Español", ssInterval: "Intervalo", ssThreshold: "Umbral"
    },
    show: {
      e1: "01 — Cifras reales", t1: ["El mismo número", "que ve tu Mac."],
      b1: "Leemos directamente el chip gas-gauge — el mismo valor FCC que el sistema usa internamente. Sin marketing, sin redondeos, sin estimaciones edulcoradas. Solo verdad cruda, expuesta con transparencia.",
      e2: "02 — Pronóstico", t2: ["Sabe cuándo", "antes de tiempo."],
      b2: "La regresión lineal sobre todo el histórico proyecta exactamente cuándo la batería caerá al 80% — y cuántos ciclos te quedan antes del servicio.",
      e3: "03 — Cada dispositivo", t3: ["Mac, iPhone, iPad.", "Una ventana."],
      b3: "Empareja una vez por USB, monitorea para siempre por Wi-Fi. Ciclos, capacidad, temperatura y voltaje para toda la familia — sin levantarte del escritorio.",
      forecastNote: "80% en ~14 meses", liveDevices: "3 dispositivos · live"
    },
    feat: {
      eyebrow: "/* funciones */",
      title: ["Todo lo que necesitas saber", "sobre tus baterías."],
      sub: "Ocho módulos, una app, cero analytics. El diagnóstico como debería ser — información pura.",
      f1t: "Salud FCC cruda", f1b: "Lee directamente el chip gas-gauge. Mismos números que usa el sistema — expuestos con transparencia.",
      f2t: "Conteo y pronóstico", f2b: "Regresión lineal: te dice cuándo la salud llegará al 80% y cuántos ciclos te quedan.",
      f3t: "Soporte iPhone y iPad", f3b: "Detalles completos vía USB o Wi-Fi con libimobiledevice. Ciclos, capacidad, temperatura, voltaje.",
      f4t: "Clasificador de adaptadores", f4b: "Identifica cargadores originales, MFi-certificados o genéricos por el valor FamilyCode IORegistry.",
      f5t: "Histórico y gráficos", f5b: "Histórico SQLite con gráficos superpuestos para todos los dispositivos. Exportación CSV.",
      f6t: "Notificaciones inteligentes", f6b: "Detección de anomalías: alerta si la salud cae más rápido de lo normal. Más batería baja, caliente, recordatorios.",
      f7t: "Localizada", f7b: "Inglés, italiano, francés, español y alemán de serie. Más idiomas bienvenidos vía PR.",
      f8t: "Privacy first", f8b: "Sin analytics, sin llamadas de red, sin cuenta. Datos en ~/Library/Application Support/BatteryMonitor.",
      f9t: "Lecturas en vivo", f9b: "Actualiza cada segundo mientras esté conectado. Mira voltaje y temperatura responder a la carga."
    },
    dl: {
      eyebrow: "/* download */",
      title: "Un clic e instalado.",
      sub: "Universal binary pre-compilado en GitHub Releases.",
      btn: "Última release · v1.4.0",
      meta: "macOS 13+ · ~6.4 MB · SHA256 verificado",
      i1t: "Primer arranque", i1b: "La app está firmada ad-hoc, así Gatekeeper avisa al primer arranque. Click derecho en .app → Abrir → confirmar. macOS recuerda la elección.",
      i2t: "Soporte iOS / iPadOS", i2b: "Instala libimobiledevice, luego conecta y autoriza el dispositivo."
    },
    build: {
      eyebrow: "/* build */",
      title: "Compila desde el código.",
      sub: "Pure Swift + SwiftUI + Swift Charts. Sin dependencias externas. ~1300 LOC.",
      meta: "Licencia MIT · Hecho con cariño para baterías de todo el mundo."
    },
    contact: {
      eyebrow: "/* contacto */",
      title: "Ponte en contacto.",
      sub: "¿Un bug, una idea o solo saludar?",
      email: "Correo", donate: "Donar", donateSub: "Apoya el desarrollo"
    },
    footer: "No afiliado a ningún fabricante · Licencia MIT · Construido con ♥ por la transparencia."
  },

  de: {
    nav: { features: "Funktionen", preview: "Vorschau", download: "Download", source: "GitHub" },
    hero: {
      badge: "v1.4 — universal binary, signiert",
      title: ["Kostenlose", "Akku-", "Diagnose", "für Mac,", "iPhone", "&", "iPad."],
      sub: "Open Source. Keine Telemetrie. Alles bleibt auf deinem Mac.",
      cta1: "Für macOS laden",
      cta2: "Auf GitHub ansehen",
      meta: "Universal Binary · Apple Silicon + Intel · macOS 13+"
    },
    dash: {
      devices: "Geräte", cycles: "Zyklen", health: "Zustand", cyclesLabel: "Zyklen",
      remaining: "713 übrig · ~3,8 Jahre", temp: "Temperatur", tempTrend: "Optimaler Bereich",
      forecastTitle: "Zustandsprognose", forecastLegend: "12 Monate · lineare Regression"
    },
    preview: {
      eyebrow: "/* vorschau */",
      title: "So sieht's aus.",
      sub: "Drei Ansichten, eine App. Alles was du brauchst, nichts mehr.",
      cap1: "Mac · Zyklen, FCC-Roh-Zustand, Echtzeit-Wattzahl, Adapter-Qualität, Verlaufsdiagramm.",
      cap2: "iPhone und iPad · per USB oder Wi-Fi mit libimobiledevice.",
      cap3: "Einstellungen · Login-Start, Log-Intervall, Sprache, Schwellen.",
      ssMac: "Mac", ssIphone: "iPhone", ssIpad: "iPad",
      ssCycles: "Zyklen", ssHealth: "Zustand (FCC)", ssCap: "Kapazität",
      ssVolt: "Spannung", ssTemp: "Temperatur", ssAdapter: "Netzteil",
      ssModel: "Modell", ssDesignCap: "Design-Kap.", ssRealCap: "Echte Kap.", ssConn: "Verbindung",
      ssSettings: "Einstellungen", ssLogin: "Bei Anmeldung", ssNotif: "Anomalie-Warnungen",
      ssLang: "Sprache", ssLangVal: "Deutsch", ssInterval: "Intervall", ssThreshold: "Schwelle"
    },
    show: {
      e1: "01 — Echte Zahlen", t1: ["Dieselbe Zahl,", "die dein Mac sieht."],
      b1: "Wir lesen den Gas-Gauge-IC direkt — denselben FCC-Wert, den das System intern verwendet. Kein Marketing, kein Runden, keine geschönte Schätzung. Nur die rohe Wahrheit, transparent offengelegt.",
      e2: "02 — Prognose", t2: ["Wisse wann,", "bevor es soweit ist."],
      b2: "Lineare Regression über deinen gesamten Verlauf zeigt genau, wann der Akku 80% erreicht — und wie viele Zyklen dir bis zum Service bleiben.",
      e3: "03 — Jedes Gerät", t3: ["Mac, iPhone, iPad.", "Ein Fenster."],
      b3: "Einmal per USB koppeln, für immer per Wi-Fi überwachen. Zyklen, Kapazität, Temperatur und Spannung für die ganze Familie — ohne den Schreibtisch zu verlassen.",
      forecastNote: "80% in ~14 Monaten", liveDevices: "3 Geräte · live"
    },
    feat: {
      eyebrow: "/* funktionen */",
      title: ["Alles was du über deine", "Akkus wissen musst."],
      sub: "Acht Module, eine App, null Analytics. Diagnose wie sie sein sollte — pure Information.",
      f1t: "Roher FCC-Zustand", f1b: "Liest den Gas-Gauge-IC direkt. Dieselben Zahlen, die intern verwendet werden — transparent offengelegt.",
      f2t: "Zyklen & Prognose", f2b: "Lineare Regression sagt dir, wann der Zustand 80% erreicht und wie viele Zyklen bleiben.",
      f3t: "iPhone- & iPad-Support", f3b: "Vollständige Details per USB oder Wi-Fi via libimobiledevice. Zyklen, Kapazität, Temperatur, Spannung.",
      f4t: "Netzteil-Klassifikator", f4b: "Erkennt Original-, MFi-zertifizierte oder generische Ladegeräte über den FamilyCode-Wert.",
      f5t: "Verlauf & Diagramme", f5b: "SQLite-basierter Verlauf mit überlagerten Diagrammen über alle Geräte. CSV-Export.",
      f6t: "Smarte Benachrichtigungen", f6b: "Anomalie-Erkennung: warnt, wenn der Zustand schneller fällt als normal. Plus schwacher Akku, Hitze, Kalibrierungserinnerung.",
      f7t: "Lokalisiert", f7b: "Englisch, Italienisch, Französisch, Spanisch und Deutsch von Haus aus. Weitere Sprachen willkommen via PR.",
      f8t: "Privacy first", f8b: "Keine Analytics, keine Netzwerkaufrufe, kein Konto. Daten in ~/Library/Application Support/BatteryMonitor.",
      f9t: "Live-Werte", f9b: "Aktualisierung jede Sekunde, solange das Gerät verbunden ist. Sieh Spannung und Temperatur unter Last reagieren."
    },
    dl: {
      eyebrow: "/* download */",
      title: "Ein Klick zum Installieren.",
      sub: "Vorgefertigte Universal Binary auf GitHub Releases.",
      btn: "Neueste Version · v1.4.0",
      meta: "macOS 13+ · ~6.4 MB · SHA256 verifiziert",
      i1t: "Erster Start", i1b: "Die App ist ad-hoc signiert, also warnt Gatekeeper beim ersten Start. Rechtsklick auf .app → Öffnen → bestätigen. macOS merkt sich das.",
      i2t: "iOS- / iPadOS-Support", i2b: "Installiere libimobiledevice, dann verbinde und vertraue dem Gerät einmal."
    },
    build: {
      eyebrow: "/* build */",
      title: "Aus Quellcode bauen.",
      sub: "Pure Swift + SwiftUI + Swift Charts. Keine Drittanbieter-Abhängigkeiten. ~1300 LOC.",
      meta: "MIT-Lizenz · Mit Sorgfalt für Akkus überall gemacht."
    },
    contact: {
      eyebrow: "/* kontakt */",
      title: "Kontakt aufnehmen.",
      sub: "Bug, Feature-Wunsch oder einfach Hallo?",
      email: "E-Mail", donate: "Spenden", donateSub: "Entwicklung unterstützen"
    },
    footer: "Mit keinem Hersteller verbunden · MIT-Lizenz · Mit ♥ für Transparenz gebaut."
  }
};

window.__LANG_NAMES__ = {
  en: "English", it: "Italiano", fr: "Français", es: "Español", de: "Deutsch"
};
window.__LANG_FLAGS__ = { en: "EN", it: "IT", fr: "FR", es: "ES", de: "DE" };

(function () {
  function getByPath(obj, path) {
    return path.split(".").reduce(function (a, k) { return a && a[k]; }, obj);
  }
  function detectLang() {
    try {
      var saved = localStorage.getItem("db_lang");
      if (saved && window.__I18N__[saved]) return saved;
    } catch (e) {}
    var nav = (navigator.language || "en").slice(0, 2).toLowerCase();
    return window.__I18N__[nav] ? nav : "en";
  }
  function applyI18n(lang) {
    var dict = window.__I18N__[lang] || window.__I18N__.en;
    document.documentElement.lang = lang;

    // Generic [data-i18n="path.key"] -> textContent
    document.querySelectorAll("[data-i18n]").forEach(function (el) {
      var v = getByPath(dict, el.getAttribute("data-i18n"));
      if (typeof v === "string") el.textContent = v;
    });
    // [data-i18n-html] -> innerHTML (for <br/> in titles)
    document.querySelectorAll("[data-i18n-html]").forEach(function (el) {
      var v = getByPath(dict, el.getAttribute("data-i18n-html"));
      if (typeof v === "string") el.innerHTML = v;
      else if (Array.isArray(v)) el.innerHTML = v.join("<br/>");
    });

    // Hero title - rebuild word spans
    var heroTitle = document.getElementById("heroTitle");
    if (heroTitle && Array.isArray(dict.hero.title)) {
      var words = dict.hero.title;
      // Find break position: simulate "Free battery diagnostics<br/>for Mac iPhone & iPad" -> break after index 2
      var html = "";
      var midIdx = Math.ceil(words.length / 2) - 1;
      // We'll break after the 3rd word (gradient on the 3rd)
      var breakAfter = 2;
      var gradientIdx = 2;
      // Adjust per language: keep title structure consistent
      words.forEach(function (w, i) {
        var grad = i === gradientIdx ? ' class="gradient-text"' : "";
        html += '<span class="word"><span' + grad + '>' + w + "</span></span> ";
        if (i === breakAfter) html += "<br/>";
      });
      heroTitle.innerHTML = html;
      // Re-trigger animation
      heroTitle.classList.remove("in");
      void heroTitle.offsetWidth;
      heroTitle.classList.add("in");
    }

    // Showcase steps - eyebrow / title (with <br/>) / body
    var showSteps = document.querySelectorAll(".showcase-step");
    [["e1","t1","b1"],["e2","t2","b2"],["e3","t3","b3"]].forEach(function (keys, i) {
      var step = showSteps[i];
      if (!step) return;
      var eb = step.querySelector(".showcase-text-eyebrow");
      var ti = step.querySelector(".showcase-text-title");
      var bo = step.querySelector(".showcase-text-body");
      if (eb && dict.show[keys[0]]) eb.textContent = dict.show[keys[0]];
      if (ti && Array.isArray(dict.show[keys[1]])) ti.innerHTML = dict.show[keys[1]].join("<br/>");
      if (bo && dict.show[keys[2]]) bo.textContent = dict.show[keys[2]];
    });

    // Forecast text inside SVG
    var fcText = document.getElementById("forecastNoteText");
    if (fcText) fcText.textContent = dict.show.forecastNote;
    var liveDev = document.getElementById("liveDevicesLabel");
    if (liveDev) liveDev.textContent = dict.show.liveDevices;

    // Lang switch label
    var cur = document.getElementById("langCurrent");
    if (cur) cur.textContent = window.__LANG_FLAGS__[lang] || lang.toUpperCase();

    // Update active state in lang menu
    document.querySelectorAll("[data-lang]").forEach(function (b) {
      b.classList.toggle("active", b.getAttribute("data-lang") === lang);
    });

    try { localStorage.setItem("db_lang", lang); } catch (e) {}
    window.__currentLang = lang;
    document.dispatchEvent(new CustomEvent("langchange", { detail: { lang: lang } }));
  }

  function initLangSwitch() {
    var btn = document.getElementById("langSwitch");
    var menu = document.getElementById("langMenu");
    if (!btn || !menu) return;
    btn.addEventListener("click", function (e) {
      e.stopPropagation();
      menu.classList.toggle("open");
    });
    document.addEventListener("click", function () { menu.classList.remove("open"); });
    menu.querySelectorAll("[data-lang]").forEach(function (b) {
      b.addEventListener("click", function () {
        applyI18n(b.getAttribute("data-lang"));
        menu.classList.remove("open");
      });
    });
  }

  document.addEventListener("DOMContentLoaded", function () {
    applyI18n(detectLang());
    initLangSwitch();
  });

  window.applyI18n = applyI18n;
})();
