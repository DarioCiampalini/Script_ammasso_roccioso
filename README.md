# Script_ammasso_roccioso

[![MATLAB](https://img.shields.io/badge/MATLAB-R2024b-orange?logo=mathworks)](https://www.mathworks.com) [![Language-MATLAB](https://img.shields.io/badge/Lang-MATLAB-007ACC)]

Script MATLAB interattivo per l'analisi strutturale di ammassi/pareti rocciose su ortofoto acquisite da drone. Fornisce una procedura guidata per calibrare il GSD, tracciare discontinuità (linee e poligoni), stimare aperture, riconoscere famiglie di orientazione tramite istogramma+picchi, calcolare spaziature lungo una fascia di stendimento e generare report CSV e una dashboard PNG.

## Caratteristiche principali
- Calibrazione GSD tramite linea di riferimento disegnata sull'immagine.
- Tracciamento interattivo di discontinuità come polilinee o poligoni (doppio click per confermare).
- Rilevamento di intercette su una fascia di stendimento centrata su una scanline (A/B).
- Classificazione automatica in famiglie (dato assiale 0–180°) con ricerca dei picchi nell'istogramma.
- Calcolo aperture: aperture misurate per poligoni; aperture di default assegnate alle linee.
- Analisi spaziature e confronto con modelli (log-normale, esponenziale).
- Output: CSV dettagliato, CSV riepilogo famiglie e PNG dashboard riepilogativa.

## Requisiti
- MATLAB (consigliato R2024b).
- Image Processing Toolbox (ROI interattive: drawline, drawpolyline, patch, ecc.).
- Statistics and Machine Learning Toolbox (fitdist) — opzionale ma necessario per il fitting delle distribuzioni nella dashboard.
- Ambiente desktop MATLAB (interazione mouse/GUI obbligatoria).

## Installazione e uso rapido
1. Aprire MATLAB e impostare working folder al repository.
2. Aprire `script_ammasso_roccioso.m`.
3. Eseguire lo script (Run).
4. Quando richiesto, selezionare l'ortofoto (formati supportati: .jpg/.jpeg/.png/.tif/.tiff).
5. Tracciare con mouse:
   - Una linea nota per la calibrazione GSD (inserire lunghezza reale in metri).
   - Le discontinuità: disegnare polilinee; chiudere il tracciato come poligono per misurare aperture reali.
   - La linea centrale della fascia di stendimento (scanline): inserire lo spessore reale della fascia (m).
6. Al termine lo script salva i file nella cartella `path_output` definita nello script.

## Percorsi e file di output (default nel codice)
- `path_input` — percorso iniziale per selezionare immagini (modificabile nello script).
- `path_output` — cartella dove vengono salvati i risultati (creata automaticamente se inesistente).
- File generati:
  - GeoScan_Pro_Report.csv — tabella dettagliata per ogni discontinuità.
  - GeoScan_Pro_Report_Famiglie.csv — riepilogo famiglie (orientazione media, conteggi).
  - GeoScan_Pro_Dashboard_AI.png — immagine dashboard con mappa, rosetta e grafici.

## Colonne principali del CSV (GeoScan_Pro_Report.csv)
- ID, Orientazione_Immagine_deg, Famiglia_ID, Famiglia_Orientazione_Media_deg, Tipo_Traccia, Lunghezza_m, Apertura_mm, Apertura_Origine, Su_Fascia, Dist_Prog_m, Spaziatura_m

## Parametri configurabili (variabili in cima al file)
- APERTURA_LINEA_DEFAULT_MM — apertura assegnata alle tracce-linea (default 2.0 mm).
- BIN_SIZE_DEG — passo dell'istogramma orientazioni (default 5°).
- MIN_PROM_FRAC, MIN_PEAK_DIST_DEG — soglie per la ricerca dei picchi nelle famiglie.
- TOLLERANZA_FAMIGLIA_DEG — tolleranza ± per l'assegnazione a una famiglia (default 30°).
- `path_input` e `path_output` — percorsi di input/output.

## Comportamento e note importanti
- Lo script è interattivo: richiede operazioni manuali (disegno ROI). Non è pensato per batch automatici senza modifica.
- Le ROI chiuse (poligoni) producono aperture "misurate" (area/lunghezza * GSD); le polilinee aperte ricevono un valore di apertura di default configurabile.
- La classificazione in famiglie è su dato assiale (periodicità 180°). Misure troppo lontane dai picchi (oltre la tolleranza) restano marcate come "Non classificata" (Famiglia_ID = 0).
- Alcune funzionalità (fitting delle distribuzioni, istogrammi avanzati) richiedono la Statistics and Machine Learning Toolbox; le ROI interattive richiedono Image Processing Toolbox.

## Esempio di flusso operativo
1. Run script → selezione immagine.
2. Disegno linea di calibrazione → inserimento lunghezza reale → GSD calcolato.
3. Tracciamento delle discontinuità (linee/poligoni).
4. Tracciamento scanline e inserimento spessore fascia.
5. Elaborazione automatica: intercette, famiglie, aperture, spaziature.
6. Salvataggio CSV e PNG in `path_output`.

## Autore
Dario Ciampalini, email: dario.ciampalini@edu.unifi.it

## Licenza
Uso accademico e di ricerca.
