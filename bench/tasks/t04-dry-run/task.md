Aggiungi a scripts/clean-cache.sh un'opzione --dry-run: stampa cosa cancellerebbe e
non cancella niente. Senza l'opzione lo script deve continuare a funzionare come oggi.
(Invariante del repo: ogni script che modifica il sistema espone --dry-run.)
