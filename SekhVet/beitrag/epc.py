import segno

# EPC069-12 (GiroCode) payload, zeilenweise. Leere Zeilen = Feld nicht gesetzt.
payload = "\n".join([
    "BCD",                      # 1 Service Tag
    "002",                      # 2 Version (002: BIC optional)
    "1",                        # 3 Zeichensatz 1 = UTF-8
    "SCT",                      # 4 SEPA Credit Transfer
    "POFICHBEXXX",              # 5 BIC
    "Kappa1-VRS GmbH",          # 6 Empfaenger (max 70)
    "CH9609000000168674143",    # 7 IBAN (EUR-Konto)
    "",                         # 8 Betrag -> leer = Zahler traegt ein
    "",                         # 9 Purpose Code
    "",                         # 10 strukturierte Referenz
    "SekhVet contribution",     # 11 unstrukturierter Verwendungszweck (max 140)
])
print(repr(payload))
assert len(payload.encode("utf-8")) <= 331
segno.make(payload, error="m").save("sekhvet-girocode-eur.png", scale=10, border=4)
print("ok -> sekhvet-girocode-eur.png")
