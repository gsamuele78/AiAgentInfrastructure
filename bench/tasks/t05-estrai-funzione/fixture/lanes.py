"""Elenco delle lane da un file di testo: una riga "nome=modello@endpoint"."""


def local_lanes(text):
    out = []
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        name, rest = line.split("=", 1)
        model, endpoint = rest.rsplit("@", 1)
        if endpoint.startswith("http://192.168.") or endpoint.startswith("http://127."):
            out.append((name.strip(), model.strip(), endpoint.strip()))
    return out


def cloud_lanes(text):
    out = []
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        name, rest = line.split("=", 1)
        model, endpoint = rest.rsplit("@", 1)
        if endpoint.startswith("https://"):
            out.append((name.strip(), model.strip(), endpoint.strip()))
    return out
