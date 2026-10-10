# shellcheck shell=bash
# ============================================================
#  llm-plan.sh -- QUALE LLM locale regge questo hardware.
#  Una sola tabella, usata da detect-hardware.sh (che la stampa) e da
#  setup-ollama.sh (che la applica). Prima ce n'erano due, divergenti.
#
#  Principio: i modelli NON si inventano qui. Sono quelli che il gateway
#  usa davvero (services/litellm_config.yaml: local-fast, local-good e il
#  primo anello di `auto`). L'hardware decide QUALI di quelli entrano, non
#  quali altri scaricare: un 14B che nessuna lane referenzia e' spazio perso,
#  e un `auto` che punta a un modello mai scaricato salta il locale in silenzio.
#
#  Funzioni pure (niente I/O di sistema): testabili con numeri finti.
# ============================================================

# Modelli del gateway e loro fabbisogno (quantizzazione Q4 di default di Ollama).
#   mem_gb  = pesi + KV cache a 16k token in q8_0 + margine runtime
#   disk_gb = dimensione del download
# Valori misurati sulle schede Ollama di qwen2.5-coder (3b: 1.9 GB, 7b: 4.7 GB);
# la KV a 16k in q8 vale ~0.5 GB per il 3B e ~0.9 GB per il 7B.
LLM_MODEL_SMALL="${LLM_MODEL_SMALL:-qwen2.5-coder:3b}"   # local-fast
LLM_MODEL_MAIN="${LLM_MODEL_MAIN:-qwen2.5-coder:7b}"     # local-good + auto
llm_mem_gb(){ case "$1" in *:3b) echo 3.0 ;; *:7b) echo 6.5 ;; *:14b) echo 11.5 ;; *) echo 0 ;; esac; }
llm_disk_gb(){ case "$1" in *:3b) echo 1.9 ;; *:7b) echo 4.7 ;; *:14b) echo 9.0 ;; *) echo 0 ;; esac; }

# RAM che il modello puo' usare davvero: il totale meno la VM del gateway
# (VM_RAM_MB, default di create-vm.sh) e meno quanto serve all'host (desktop,
# IDE, agenti). Contare la RAM "libera" del momento renderebbe la scelta
# casuale: dipenderebbe da quanti tab ha aperto il browser.
llm_usable_ram_gb(){
  local total_gb=$1 vm_gb host_gb=${LLM_HOST_RESERVE_GB:-4}
  vm_gb=$(( (${VM_RAM_MB:-4096} + 1023) / 1024 ))
  local u=$(( total_gb - vm_gb - host_gb )); [ "$u" -lt 0 ] && u=0; echo "$u"
}

# confronto decimale senza bc: llm_ge A B  ->  A >= B
llm_ge(){ awk -v a="$1" -v b="$2" 'BEGIN{exit !(a+0 >= b+0)}'; }

# llm_plan VRAM_MB RAM_TOTAL_GB DISK_FREE_GB
# Stampa UNA riga:  VERDICT|MODELS|LAYERS|NOTE
#   VERDICT  gpu (tutto in VRAM) · gpu-offload (parte in RAM) · cpu · none
#   MODELS   modelli da scaricare, separati da spazio (vuoto se none)
#   LAYERS   stima dei layer del modello principale in GPU (solo gpu-offload):
#            Ollama li calcola da solo, il numero serve a capire, non a forzare
#   NOTE     motivo, leggibile
llm_plan(){
  local vram_mb=${1:-0} ram_gb=${2:-0} disk_gb=${3:-0}
  local vram_gb usable small="$LLM_MODEL_SMALL" main="$LLM_MODEL_MAIN"
  vram_gb=$(awk -v v="$vram_mb" 'BEGIN{printf "%.1f", v/1024}')
  usable=$(llm_usable_ram_gb "$ram_gb")
  local need_main need_small disk_both disk_small
  need_main=$(llm_mem_gb "$main"); need_small=$(llm_mem_gb "$small")
  disk_both=$(awk -v a="$(llm_disk_gb "$small")" -v b="$(llm_disk_gb "$main")" 'BEGIN{print a+b+2}')
  disk_small=$(awk -v a="$(llm_disk_gb "$small")" 'BEGIN{print a+2}')

  # 1. Disco prima di tutto: un pull a meta' lascia blob orfani e un servizio inutile.
  if ! llm_ge "$disk_gb" "$disk_small"; then
    echo "none|||disco: ${disk_gb} GB liberi, ne servono almeno ${disk_small} per $small"; return
  fi
  # 2. GPU con VRAM sufficiente per il principale: tutto in VRAM.
  if [ "$vram_mb" -gt 0 ] && llm_ge "$vram_gb" "$need_main"; then
    if llm_ge "$disk_gb" "$disk_both"; then
      local note="entrambi in VRAM (${vram_gb} GB)"
      [ "$vram_mb" -ge 40000 ] && note="$note; fascia server: per piu' utenti usa vLLM (docs/BIOME-L40S.md)"
      echo "gpu|$small $main||$note"
    else echo "gpu|$small||disco: solo $small entra (${disk_gb} GB liberi)"; fi
    return
  fi
  # 3. GPU piccola (>= 3.5 GB): il 3B in VRAM, il 7B in offload se la RAM lo regge.
  if [ "$vram_mb" -ge 3500 ]; then
    if llm_ge "$(awk -v v="$vram_gb" -v u="$usable" 'BEGIN{print v+u}')" "$need_main" \
       && llm_ge "$disk_gb" "$disk_both"; then
      # layer in GPU ~ 28 layer * (VRAM - 1 GB di KV/runtime) / 4.7 GB di pesi
      local layers
      layers=$(awk -v v="$vram_gb" 'BEGIN{l=int(28*(v-1)/4.7); if(l<1)l=1; if(l>28)l=28; print l}')
      echo "gpu-offload|$small $main|$layers|$small in VRAM; $main ~${layers}/28 layer in GPU, il resto in RAM (${usable} GB utilizzabili)"
    else
      echo "gpu|$small||$small in VRAM; RAM utilizzabile ${usable} GB: $main non entra, 'auto' salta il locale"
    fi
    return
  fi
  # 4. Solo CPU (nessuna GPU utile). Il 7B girerebbe a 2-5 token/s: come primo
  #    anello di `auto` renderebbe ogni sessione d'agente piu' lenta del cloud.
  #    Si scarica solo il 3B (local-fast: batch, FIM) e `auto` va al cloud.
  if llm_ge "$usable" "$need_small"; then
    echo "cpu|$small||nessuna GPU utilizzabile: solo $small su CPU (lento); 'auto' salta il locale per scelta"
  else
    echo "none|||RAM utilizzabile ${usable} GB (totale ${ram_gb} - VM - host): non basta neanche per $small"
  fi
}
