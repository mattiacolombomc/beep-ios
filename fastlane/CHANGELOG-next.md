# Changelog per la prossima build TestFlight

Testo da passare a `distribute_external` (`"changelog:…"`), iOS e Mac:

Errori: quando WeBeep è in manutenzione Beep riconosce la sua pagina, ne riporta il testo in un avviso in cima ai corsi e nel riquadro Sync, e toglie l'avviso appena WeBeep risponde di nuovo; tutti i messaggi di errore sono ora leggibili. Le notifiche dei quiz e delle consegne, che non hanno il link al corso, vengono associate al corso dal nome.

Errors: when WeBeep is down for maintenance Beep recognises its page, quotes it in a notice above the courses and in the Sync tile, and clears the notice as soon as WeBeep answers again; every error message is now readable. Quiz and assignment notifications, which carry no course link, are matched to their course by name.

Download: un tocco sull'icona rossa di un file non scaricato mostra l'errore, con una spiegazione e "Riprova". Se il sistema interrompe il servizio di download in background, Beep riapre la connessione e riprova da solo.

Downloads: tapping the red icon of a file that failed to download shows the error, with an explanation and "Try again". When the system drops the background download service, Beep opens a new connection and retries on its own.

Semestre: nel menu Filtri c'è il nuovo filtro "Periodo" (semestre in corso, 1°, 2°), il filtro "Anni" elenca anche i singoli anni accademici, e ogni corso mostra il suo semestre accanto all'anno. Il dato arriva dal catalogo pubblico del Politecnico (i Manifesti degli Studi), letto dopo ogni sincronizzazione e ricontrollato ogni settimana per i corsi dell'anno in corso; dal menu contestuale del corso si può impostare a mano. La prima volta che si usa il filtro, un pannello spiega cosa sta succedendo e mostra l'avanzamento.

Semester: the Filters menu gains a "Period" filter (current semester, 1st, 2nd), the "Years" filter also lists each academic year, and each course shows its semester next to the year. The data comes from Politecnico's public course catalogue, read after every sync and checked again weekly for current-year courses; the course context menu lets you set it by hand. The first time you use the filter, a panel explains what is going on and shows the progress.

Notifiche: l'elenco mostra il corso con il suo riquadro colorato e il titolo dell'annuncio; il dettaglio si apre nello stesso foglio, con il pulsante indietro, e mostra solo il testo dell'annuncio con autore e data (via il percorso "Forum » Annunci", l'avatar e i link di piè di pagina di WeBeep). Il testo compare all'istante, senza la pagina bianca di prima; i link si aprono nel browser.

Notifications: the list shows the course with its coloured tile and the announcement title; the detail opens inside the same sheet, with a back button, and shows only the announcement text with author and date (the "Forum » Announcements" breadcrumb, the avatar and WeBeep's footer links are gone). The text shows up at once, without the blank page; links open in the browser.
