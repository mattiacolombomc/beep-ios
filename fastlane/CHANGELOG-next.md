# Changelog per la prossima build TestFlight

Testo da passare a `distribute_external` (`"changelog:…"`), iOS e Mac:

Sincronizzazione: quando un docente modificava una cartella su WeBeep, Beep considerava nuovi tutti i file della cartella e li riscaricava tutti, anche quelli rimasti identici. Ora riconosce i file invariati: scarica solo quelli aggiunti o modificati davvero, e i pallini e le notifiche di "nuovi file" segnalano solo novità reali.

Stabilità: risolta la causa principale di una chiusura improvvisa su Mac, che avveniva aprendo una cartella di un corso dopo che la sincronizzazione ne aveva ricreato i file.

Al primo avvio di questa versione Beep aggiorna una volta l'archivio locale: i file già scaricati restano scaricati.

Sync: when a teacher edited a folder on WeBeep, Beep treated every file in that folder as new and downloaded them all again, even the unchanged ones. It now recognises unchanged files: only files that were really added or modified are downloaded, and the "new files" badges and notifications report real news only.

Stability: fixed the main cause of a sudden quit on Mac, which happened when opening a course folder after a sync had recreated its files.

On the first launch of this version Beep updates its local library once: files you already downloaded stay downloaded.
