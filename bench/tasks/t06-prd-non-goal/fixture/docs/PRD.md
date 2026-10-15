# PRD — Gateway AI a maintainer singolo

## 1. Obiettivo
Un endpoint unico per gli agenti di una workstation.

## 2. Requisiti
- F1 endpoint OpenAI-compatibile unico
- F2 routing multi-provider con fallback

## 3. Non-obiettivi (espliciti)
- Alta disponibilità / clustering: è una workstation; il rollback è lo snapshot.
- Multi-tenancy.

## 4. Vincoli
Manutenzione < 30 min/mese.
