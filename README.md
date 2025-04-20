# DnsBackup

Backup și restaurare pentru configurarea DNS pe Windows Server (2003 până în 2022).

Acest proiect oferă scripturi pentru:

- Export fișiere `.dns`
- Export configurații din registry (doar zone active)
- Generare automată `zones.csv` pentru reconstruire controlată
- Import fișiere + registry + reconfigurare zone
- Reset complet al configurației DNS

---

## 📁 Structura propusă

```plaintext
DnsBackup/
├── scripts/               # Scripturi .bat și .ps1 pentru export/import/reset
│   ├── export-dns.bat
│   ├── import-dns.bat
│   ├── reset_dns_zones.ps1
│   ├── generate_zones_csv.ps1
│   └── generate_zones_from_backup.ps1
├── docs/                 # Documentație, exemple, explicații
│   └── structure.md
├── logs/                 # Loguri de execuție (opțional)
├── backups/              # Unde se vor salva exporturile DNS
├── .gitignore            # Ignoră fișiere generate automat
└── README.md             # Acest fișier
```

---

## 🧰 Cerințe minime

- Windows Server 2003 / 2008 / 2012 / 2016 / 2019 / 2022
- PowerShell (minim v2 pentru generare CSV, v5 recomandat pentru tot)
- Pentru 2003: CMD / .bat, fără PowerShell necesar

---

## 🔁 Flux recomandat

### 🔹 Pe serverul vechi (ex: 2003)

```cmd
scripts\export-dns.bat export
```

> Se generează un folder cu fișiere `.dns`, `dns_config.reg`, `dns_zones.reg`

### 🔹 Pe serverul nou (2016+)

```powershell
# 1. Restore registry & fișiere
scripts\import-dns.bat import C:\cale\spre\backup

# 2. Generează zones.csv
powershell -ExecutionPolicy Bypass -File scripts\generate_zones_from_backup.ps1 -BackupPath "C:\cale\spre\backup"

# 3. Reconfigurează zonele
powershell -ExecutionPolicy Bypass -File scripts\recreate_zones.ps1 -CsvPath "C:\cale\spre\backup\zones.csv"
```

---

## 🧹 Resetare completă DNS Server (atenție!)

```powershell
powershell -ExecutionPolicy Bypass -File scripts\reset_dns_zones.ps1
```

> ⚠️ Acest script șterge tot (registry + fișiere + zone active) fără backup!

---

## 🔍 Diagnostic & Testare automată

În curând: integrare GitHub Actions pentru testare sintactică și funcțională.

---

## 📄 Licență

MIT. Poți folosi, modifica și redistribui liber.

---

## 🙋‍♂️ Contribuții

Toate contribuțiile sunt binevenite!
- Probleme, feature request-uri și PR-uri sunt încurajate.

---

## 📬 Contact

[github.com/cremenescu](https://github.com/cremenescu)

---
