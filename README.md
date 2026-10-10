# WorkHub

Contenitore macOS per Gmail, Slack, Google Calendar, Claude, ChatGPT e WhatsApp. App nativa Swift + WebKit, nessuna dipendenza.

## Build e installazione

Requisiti: macOS 12 o successivo, Xcode Command Line Tools (`xcode-select --install`).

Dalla cartella del progetto:

```bash
./setup-signing.sh      # una volta sola: crea il certificato "WorkHub Dev"
./build.sh install      # compila, installa in /Applications e avvia
./build.sh dmg          # oppure: crea WorkHub-<versione>.dmg da aprire e trascinare in Applicazioni
```

Se apri WorkHub da fuori Applicazioni (DMG, Download, cartella di build), propone di spostarsi lì da sola.
Dal menu WorkHub puoi attivare "Apri all'avvio del Mac" (macOS 13 o successivo).
Per tenerla nel Dock: click destro sull'icona > Opzioni > Mantieni nel Dock.

Con il certificato la firma resta uguale tra una build e l'altra, quindi macOS non richiede di nuovo
l'accesso al portachiavi né il microfono. La prima build firmata lo chiede un'ultima volta:
inserisci la password del Mac e scegli "Always Allow".

Altri Mac: il DMG funziona, ma senza un certificato Developer ID di Apple macOS mostrerà l'avviso
"sviluppatore non identificato" (si sblocca da Impostazioni di Sistema > Privacy e sicurezza > Apri comunque).

## Primo avvio

1. Consenti le notifiche quando macOS lo chiede.
2. Fai login in ogni servizio. Gmail e Calendar condividono la sessione Google, quindi basta un login.
3. WhatsApp: scansiona il QR dal telefono.
4. Attiva le notifiche desktop dentro i servizi che le hanno spente di default:
   Gmail (Impostazioni > Generali > Notifiche desktop) e Calendar (Impostazioni > Notifiche).

I login restano salvati tra un avvio e l'altro.

## Uso

| Azione | Scorciatoia |
|---|---|
| Vai al servizio 1–6 | ⌘1 … ⌘6 |
| Apri/chiudi il pannello Todos | ⌘T (o l'icona nella barra destra) |
| Apri/chiudi il pannello Focus | ⌘⇧F (o il cronometro nella barra destra) |
| Ricarica servizio / tutti | ⌘R / ⌘⇧R |
| Torna alla pagina iniziale del servizio | ⌘⇧H |
| Indietro / Avanti | ⌘[ / ⌘] |
| Nascondi finestra (i servizi restano attivi) | ⌘W |

Link esterni: si aprono nel browser predefinito. ⌘+click forza il browser anche per link interni.
Download: finiscono in ~/Downloads.

## Todos

Pannello a destra con due liste: Personal e Work.

- Invio nel campo "Add a todo..." aggiunge in cima alla lista aperta.
- Cerchio: completa. I completati finiscono nella sezione "N done", richiudibile.
- Trascina un todo su o giù per riordinarlo; trascinalo sul nome dell'altra lista (in alto) per spostarlo lì.
  Esc durante il trascinamento annulla.
- Doppio click sul testo: modifica (testo vuoto = elimina). La × compare al passaggio del mouse.
- Scadenza: icona calendario al passaggio del mouse (più tardi oggi, domani alle 9, lunedì prossimo,
  oppure data e ora a scelta). L'etichetta è rossa se scaduto, blu se scade oggi.
- Alla scadenza arriva una notifica macOS (anche con WorkHub chiusa) con "Mark as done" e
  "Remind me in 1 hour"; cliccandola si apre il pannello sul todo. L'icona Todos mostra quanti sono scaduti.
- Dati: `~/Library/Application Support/WorkHub/todos.json`, salvati a ogni modifica.

## Focus

Timer Pomodoro nella barra destra: 25 minuti di focus, 5 di pausa, e si ripete finché premi Stop.

- Start focus avvia il ciclo; Pause/Resume, Skip passa subito alla fase successiva, Stop azzera.
  Spazio avvia o mette in pausa quando il pannello è attivo.
- Il timer continua anche a pannello chiuso: l'anello attorno al cronometro nella barra mostra
  l'avanzamento (blu = focus, verde = pausa) e il tooltip il tempo che manca.
- A ogni cambio di fase arriva una notifica; cliccandola si apre il pannello.
- Suono di sottofondo: suona durante il focus e sfuma in pausa. Nel pannello scegli il suono
  (fuori dal focus, toccandolo ne senti 6 secondi di anteprima), il volume e l'interruttore.
  I suoni hanno lo stesso volume percepito e si ripetono senza stacchi.
- I suoni stanno in `~/Library/Application Support/WorkHub/Sounds/` (la cartella `Sounds/` del progetto
  viene copiata lì da `build.sh`). Per aggiungerne: "Add sounds…" nel pannello, o copia file m4a, mp3,
  wav o caf nella cartella. Non sono inclusi nell'app né nel DMG.
- Conta le sessioni di focus completate oggi (una sessione saltata non conta).

## Impostazioni (⌘,)

- **Services**: aggiungi servizi dal catalogo (Gmail, Outlook, Teams, Slack, Notion, Linear, WhatsApp,
  Telegram…) o qualsiasi sito; riordina trascinando (l'ordine vale anche per ⌘1–9); cambia nome,
  indirizzo, badge e icona; "Sign out and reset data" esce dal servizio cancellandone i dati.
- **Notifications**: pausa per 1 ora o fino a domani, contenuto nascosto, notifiche e suono per servizio,
  silenzio durante il focus con le eccezioni che scegli.
- **Focus**: durate, pausa lunga ogni N sessioni, avvio automatico della fase successiva o attesa del click,
  suono di fine fase.

Tutto si applica subito e viene salvato in `~/Library/Application Support/WorkHub/settings.json`.
Altre cartelle utili: `icons/` (icone personalizzate), `Sounds/` (suoni del Focus), `todos.json`.

Avvio automatico: menu WorkHub > "Apri all'avvio del Mac". Per tenerla nel Dock: click destro sull'icona >
Opzioni > Mantieni nel Dock.

## Limiti noti

- Badge Slack: legge il DOM di Slack, che cambia spesso. Se il badge non compare, i selettori sono in
  `Sources/Scripts.swift` (`badgeTemplate`, modalità `slack`). Per ispezionare la pagina: Safari > Sviluppo > WorkHub.
- Badge Gmail: conta i non letti della Posta in arrivo.
- Calendar, Claude e ChatGPT non hanno badge, solo notifiche dove previste.
- Le notifiche push a servizio "dormiente" (service worker in background) non sono supportate da WebKit
  nelle app: le notifiche arrivano finché l'app è aperta, anche con la finestra chiusa.
