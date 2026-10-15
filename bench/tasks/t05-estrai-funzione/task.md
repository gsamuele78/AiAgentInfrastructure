In lanes.py le funzioni local_lanes() e cloud_lanes() ripetono lo stesso parsing di una
riga "nome=modello@endpoint". Estrai il parsing in una funzione parse_lane(line) che
restituisce (nome, modello, endpoint) e usala in entrambe. Il comportamento non cambia:
test_lanes.py deve restare verde, senza modificarlo.
