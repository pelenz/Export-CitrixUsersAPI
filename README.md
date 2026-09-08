# Citrix Monitor – měsíční export uživatelů

PowerShell skript pro export unikátních uživatelů z on-premise Citrix Monitor OData API. Za zvolený počet posledních dokončených měsíců vytvoří samostatná CSV a v konzoli zobrazí měsíční počty uživatelů.

## Funkce

- Export posledních N dokončených měsíců; aktuální měsíc se vynechává.
- Samostatné CSV pro každý měsíc.
- Jeden řádek na unikátní `UserId` v rámci měsíce.
- Zahrnutí prvních připojení i reconnectů.
- NTLM autentizace pomocí aktuálního Windows účtu, bez zadávání hesla ve skriptu.
- Podpora HTTP i HTTPS.
- Načtení všech stránek výsledků API.
- Převod hranic měsíců z českého časového pásma do UTC, včetně letního času.

## Požadavky

- Windows s PowerShellem 5.1 nebo novějším.
- Dostupný on-premise Citrix Monitor OData v4 endpoint.
- Windows účet s oprávněním číst požadovaná data v Citrix Monitor API.
- Právo zápisu do výstupní složky.
- Pro HTTPS musí být certifikát serveru důvěryhodný.

Skript používá endpoint:

```text
http[s]://<server>/Citrix/Monitor/OData/v4/Data/
```

Zadejte server s Monitor Service. Nemusí jít o stejný server, na kterém běží web Directoru.

## Použití

1. Uložte skript jako `Export-CitrixUsers.ps1`.
2. Upravte nastavení na začátku souboru:

   ```powershell
   $Server     = 'http://DDC01.example.local'
   $MonthsBack = 3
   $OutputDir  = $PSScriptRoot
   ```

   | Nastavení | Význam |
   | --- | --- |
   | `$Server` | Adresa serveru včetně `http://` nebo `https://`, bez cesty k API. Pokud protokol chybí, doplní se HTTP. |
   | `$MonthsBack` | Počet posledních dokončených měsíců. Celé číslo větší než nula. |
   | `$OutputDir` | Složka pro CSV. Výchozí `$PSScriptRoot` znamená složku se skriptem. |

3. Spusťte skript v PowerShellu pod účtem s přístupem do Citrix Monitoru:

   ```powershell
   .\Export-CitrixUsers.ps1
   ```

Skript automaticky použije aktuální Windows účet přes NTLM. Nezobrazuje výzvu k zadání přihlašovacích údajů.

Pro HTTPS například nastavte:

```powershell
$Server = 'https://DDC01.example.local'
```

## Výstupy

Při spuštění v září 2026 s `$MonthsBack = 3` vzniknou soubory:

```text
Citrix-Users-2026-08.csv
Citrix-Users-2026-07.csv
Citrix-Users-2026-06.csv
```

CSV používá oddělovač `;` a kódování UTF-8. Soubory se stejným názvem se při dalším spuštění přepíšou. Měsíc bez výsledků vytvoří CSV pouze s hlavičkou.

| Sloupec | Význam |
| --- | --- |
| `Month` | Měsíc ve formátu `YYYY-MM`. |
| `UserId` | Identifikátor uživatele v Citrix Monitoru. |
| `UserName` | Uživatelské jméno vrácené API. |
| `ConnectionCount` | Počet evidovaných připojení v měsíci včetně reconnectů. |
| `ReconnectCount` | Počet reconnectů v měsíci. Jde o podmnožinu `ConnectionCount`. |

Na konci se zobrazí přehled od nejstaršího měsíce, například:

```text
Mesic   Uzivatele
-----   --------
2026-06       51
2026-07       55
2026-08       49
```

Čísla v ukázce jsou ilustrativní. Přehled se vypisuje do konzole; neukládá se do samostatného souhrnného souboru.

## Jak se počítají uživatelé

Skript čte entitu `Connections` a filtruje podle `EstablishmentDate`: času, kdy VDA potvrdilo připojení nebo reconnect. Interval začíná prvním dnem měsíce v 00:00 v českém časovém pásmu a končí začátkem dalšího měsíce, který se už nezahrnuje.

Připojení se propojí s uživatelem přes `Session/User`. Duplicitní připojení se odstraní podle `Id` a výsledky se seskupí podle `UserId`. Počet těchto skupin odpovídá počtu řádků uživatelů v CSV, bez hlavičky.

Stejný uživatel může být zahrnut ve více měsících, ale v každém měsíci jen jednou. Součet měsíčních počtů proto není počtem unikátních uživatelů za celé období.

Report zachycuje připojení uskutečněná během měsíce. Uživatel, který zůstal připojený z minulého měsíce a v daném měsíci neprovedl nové připojení ani reconnect, se tímto filtrem nezahrne. Záznamy bez dostupného `Session/User` nebo `UserId` se vynechávají.

## Omezení a ověření výsledků

- Historické výsledky závisí na dostupnosti detailních dat v Monitor databázi. Prázdné CSV samo o sobě nepotvrzuje, že se v daném měsíci nikdo nepřipojil.
- Výsledky mohou být omezené oprávněním účtu.
- Při porovnání s custom reportem v Directoru musí odpovídat časové pásmo, filtry a definice připojení.
- Při chybě se skript zastaví. CSV za měsíce dokončené před chybou zůstávají uložená.

## Řešení potíží

| Problém | Co zkontrolovat |
| --- | --- |
| HTTP 401 | Aktuální Windows účet a dostupnost NTLM autentizace na serveru. |
| HTTP 403 | Oprávnění účtu k požadovaným datům. |
| HTTP 404 | Adresu serveru a dostupnost OData v4 endpointu. |
| HTTP 400 | Podporu použitých polí a dotazu ve vaší verzi API. |
| Chyba certifikátu | Důvěryhodnost certifikátu a shodu jména serveru s certifikátem. |
| Prázdný nebo neúplný report | Retenci dat, oprávnění účtu a zvolený interval. |
| Spuštění skriptu je blokováno | Pravidla spouštění PowerShell skriptů ve vaší organizaci. |

## Obsah repozitáře

```text
Export-CitrixUsers.ps1
README.md
.gitignore
```

Vygenerovaná CSV obsahují uživatelská data. Pro jejich vynechání z Gitu přidejte do `.gitignore`:

```gitignore
Citrix-Users-*.csv
```

## Dokumentace

- [Citrix Monitor API – Sessions a on-premise endpoint](https://developer-docs.citrix.com/en-us/monitor-service-odata-api/how-to-get-sessions)
- [Citrix Monitor API – Connections](https://developer-docs.citrix.com/en-us/monitor-service-odata-api/how-to-get-connections)
- [Citrix Monitor OData – datový model](https://developer-docs.citrix.com/en-us/monitor-service-odata-api/api-reference/monitor-model)
