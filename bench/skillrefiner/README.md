# SkillRefiner sulle nostre tracce (rinviato finché non ci sono dati)

[SkillRefiner](https://github.com/OpenHands/SkillRefiner) (MIT, provato al commit
`9a03ded`) migliora una skill **offline**, partendo da tracce passate già etichettate:
riassume i successi e i fallimenti, li raggruppa, propone modifiche e tiene quelle
derivate dai fallimenti solo se le tracce le sostengono. Non genera nuovi rollout. Gli
embedding di default girano su **Ollama locale** (`qwen3-embedding:4b`), che si sposa
con la lane locale ([ADR-0025](../../docs/adr/0025-pratiche-openhands-importate-con-misura.md) §11).

Cosa si importa ora: **il formato dei dati**. `bench/tasks/run.sh` salva ogni run con
il suo esito deterministico, `export.py` lo converte nei due file che SkillRefiner chiede.

```bash
bench/skillrefiner/export.py bench/results/tasks-* --task t01 --out /tmp/sr-t01
```

Perché non oltre:
- **non ci sono ancora skill di repo** da raffinare (`adr`, `infra-change` arrivano con P4);
- servono almeno 3 successi **e** 3 fallimenti per task, e il paper usa 200–639 tracce:
  con 10 golden task × 5 ripetizioni siamo un ordine di grandezza sotto;
- SkillRefiner vuole i suoi pin (`uv sync`) e tre servizi (LLM, embedding, tmux): si
  installa in un ambiente a parte, **non** diventa una dipendenza del repo.

Gate (pre-registrato): si prova quando una skill di repo ha ≥ 30 tracce per lato. Si
adotta la skill proposta solo se, su un insieme di task **separato** da quello delle
tracce, il pass@1 sale di ≥ 10 punti senza costo per task risolto oltre +10 %
(ADR-0021 §5).
