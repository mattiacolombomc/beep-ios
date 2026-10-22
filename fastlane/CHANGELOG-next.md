# Changelog per la prossima build TestFlight

Testo da passare a `distribute_external` (`"changelog:…"`), iOS e Mac:

Stabilità: risolto un crash in background su iPad dopo una sincronizzazione. L'indice Spotlight veniva ricostruito da un'attività che iOS poteva sospendere a metà e riprendere ore dopo, quando la sync successiva aveva già cancellato dei file; ora l'indice si costruisce da una fotografia dei dati presa insieme alla sync.

Stability: fixed a background crash on iPad after a sync. The Spotlight index was rebuilt by a task that iOS could suspend half-way and resume hours later, once the next sync had already deleted files; the index is now built from a snapshot taken together with the sync.
