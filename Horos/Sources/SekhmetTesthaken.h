// Teil des SekhVet-Forks von Horos, LGPL-3.0.
// SekhVet: Testhaken (Umgebungsvariablen SEKHVET_*_TEST, SEKHVET_SKIP_DISCLAIMER,
// SEKHVET_DICOMWEB_PW) gibt es NUR in einem Build mit dem Flag SEKHVET_TESTHAKEN=1.
// Ohne das Flag liefert sekhvetTesthaken() immer NULL, der Compiler entfernt die
// Zweige, und das Binary enthaelt die Variablennamen nicht (Nachweis:
// `strings Horos.app/Contents/MacOS/Horos | grep -c SEKHVET_` = 0).
//
// Grund (Review 12.09.2026): jede SEKHVET_*_TEST-Variable uebersprang den
// Medizinprodukt-Hinweis, das Passwort kam aus der Umgebung, Import/STOW/WADO
// liefen 20 s nach dem Start ohne GUI — im ausgelieferten Release.
//
// Headless-Testlauf (Release-Konfiguration, weil Debug an VTK-Asserts haengt):
//   xcodebuild ... -configuration Release -xcconfig SekhVet/SekhVet-Testhaken.xcconfig
// (OTHER_CFLAGS inline scheitert an der Shell-Quotierung von $(inherited).)
// Danach OHNE die xcconfig neu bauen, bevor die App installiert oder weitergegeben wird.
#ifndef SEKHVET_TESTHAKEN_H
#define SEKHVET_TESTHAKEN_H

#include <stdlib.h>

#ifndef SEKHVET_TESTHAKEN
#define SEKHVET_TESTHAKEN 0
#endif

#if SEKHVET_TESTHAKEN
static inline const char *sekhvetTesthaken( const char *name) { return getenv( name); }
#else
// Makro, kein inline: so erreicht das "SEKHVET_..."-Literal den Compiler gar
// nicht erst -- die Garantie haengt nicht daran, dass -Os den toten Aufruf streicht.
#define sekhvetTesthaken( name) ((const char*) NULL)
#endif

#endif
