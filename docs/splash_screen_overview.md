# polsoft.ITS(TM) Developers Splash Screen & Tools Hub

Grafika oraz interaktywny launcher / panel nawigacyjny (**Tools Hub**) łączący wszystkie 9 narzędzi z pakietu.

![polsoft.ITS Developers Splash Screen](C:/Users/max/.gemini/antigravity-ide/brain/8fefb0d3-ca6c-4752-bcf8-7b4b4b3c7816/splash_screen_1793287586208.jpg)

---

### Działanie dwufazowe:
1. **Faza 1 – Splash Screen**:
   - Wyświetla nowoczesny ekran startowy z logo, brandingiem i odliczaniem czasu (domyślnie 3 sekundy).
   - Użytkownik może kliknąć w dowolnym miejscu lub wcisnąć `Enter`/`Spację`/przycisk `Enter Tools Hub >>`, aby przejść od razu do pulpitu narzędzi.
2. **Faza 2 – Tools Hub (Pulpit Narzędzi)**:
   - Okno płynnie przełącza się w nowoczesny panel kafelkowy (siatka 3x3).
   - Dynamicznie sprawdza obecność każdego z 9 skryptów w katalogu (`[READY]` / `[MISSING]`).
   - Pozwala uruchomić dowolne narzędzie jednym kliknięciem przycisku **Launch**.
   - Kliknięcie w link **GitHub** otwiera profil `https://github.com/polsoft-it` w przeglądarce.
   - Kliknięcie w **Email** kopiuje `polsoft.its@mail.com` bezpośrednio do schowka.

---

### Obsługiwane narzędzia w Hubie:
| Karta w Hubie | Plik | Opis |
| :--- | :--- | :--- |
| **isoMicrosoft** | `isoMicrosoft.ps1` | Uniwersalny pobieracz Windows & Office z inteligentną ankietą |
| **isoWindows** | `isoWindows.ps1` | Oficjalny pobieracz Windows 11, 10, 8.1 przez Microsoft API |
| **isoOffice** | `isoOffice.ps1` | Pobieracz pakietów Office 2024, 2021, 2019, 2016 |
| **isoLinux** | `isoLinux.ps1` | Dystrybucje Linux & Proxmox VE (Ubuntu, Debian, Fedora itp.) |
| **isoRescue** | `isoRescue.ps1` | Obrazy ratunkowe i diagnostyczne (Hiren's, Rescuezilla itp.) |
| **isoServer** | `isoServer.ps1` | Obrazy Windows Server (2025, 2022, 2019, 2016) |
| **odtConfig** | `odtConfig.ps1` | Generator XML dla Office Deployment Tool + instalator ODT |
| **isoVerify** | `isoVerify.ps1` | Weryfikator sum kontrolnych, podpisów i bazy MSDN |
| **isoVentoy** | `isoVentoy.ps1` | Menedżer USB Ventoy, reguły ominięcia Win11 i kopiarka ISO |

---

### Przykłady uruchomienia:
```powershell
# Standardowe uruchomienie (Splash 3s -> Przejście do Tools Hub):
.\splashScreen.ps1

# Bezpośrednie otwarcie Dashboardu (z pominięciem Splash Screena):
.\splashScreen.ps1 -SkipSplash

# Tylko ekran powitalny (zamknięcie po 3s bez otwierania Hubu):
.\splashScreen.ps1 -SplashOnly
```
