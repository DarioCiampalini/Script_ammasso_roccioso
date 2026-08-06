%% GEOSCAN PRO - WORKFLOW STRUTTURALE AVANZATO (R2024b)
% v4 - Modifiche rispetto alla versione precedente (v3):
%
%   1) FASCIA DI STENDIMENTO (in luogo della singola scanline):
%      - Si traccia ancora una linea centrale (drawline), ma subito dopo
%        viene chiesto lo SPESSORE reale della fascia (in metri).
%      - Viene costruito un rettangolo (poligono a 4 vertici) centrato
%        sulla linea, di larghezza pari allo spessore inserito.
%      - Una discontinuità è "intercettata" se una sua porzione (lato
%        della poli-linea/poligono oppure un vertice) cade dentro la
%        fascia: si verifica sia l'intersezione segmento-segmento con i
%        4 lati del rettangolo, sia il contenimento dei vertici tramite
%        inpolygon. Il punto di intercetta usato per la progressiva
%        lungo lo stendimento è il baricentro dei punti trovati,
%        proiettato sulla linea centrale della fascia.
%
%   2) RICONOSCIMENTO FAMIGLIE tramite istogramma + ricerca dei picchi
%      (invece dei 4 intervalli fissi a 45°):
%      - Le orientazioni sono dato ASSIALE (periodicità 180°): vengono
%        ricondotte in [0,180).
%      - Si costruisce un istogramma a passo BIN_SIZE_DEG (default 5°)
%        e si "triplica" circolarmente (centri-180, centri, centri+180)
%        per poter individuare correttamente anche i picchi vicini al
%        bordo 0°/180°.
%      - I picchi vengono individuati con un algoritmo scritto "a mano"
%        (massimi locali + prominenza + soppressione dei picchi troppo
%        vicini), analogo a findpeaks ma SENZA richiedere il Signal
%        Processing Toolbox. Soglie di prominenza e distanza minima
%        configurabili (MIN_PROM_FRAC, MIN_PEAK_DIST_DEG).
%      - Ogni discontinuità viene assegnata alla famiglia il cui picco è
%        più vicino in senso circolare (distanza mod 180°), ma SOLO se
%        rientra nella tolleranza ±TOLLERANZA_FAMIGLIA_DEG (default 30°)
%        dal picco: oltre questa soglia la discontinuità resta "Non
%        classificata" (Famiglia_ID = 0), invece di essere comunque
%        forzata nella famiglia più vicina.
%      - Il numero di famiglie NON è più fisso: viene determinato
%        automaticamente dai dati.
%
%   1b) ESTREMITÀ A/B della fascia di stendimento:
%      - Le due estremità della linea centrale della fascia vengono
%        etichettate "A" (primo punto tracciato) e "B" (secondo punto),
%        sia sull'immagine di lavoro sia nella dashboard finale, per
%        poter riferire in modo univoco le progressive (distanza da A).
%
%   3) APERTURA per TUTTE le discontinuità (non solo i poligoni):
%      - Se la traccia è un poligono chiuso: apertura = (area/lunghezza)
%        * GSD * 1000, come in v3 (misura reale).
%      - Se la traccia è una linea aperta (senza spessore disegnato):
%        viene assegnata un'apertura convenzionale di DEFAULT
%        (APERTURA_LINEA_DEFAULT_MM, default 2 mm), anziché NaN.
%      - L'apertura media viene quindi calcolata su TUTTE le
%        discontinuità tracciate, distinguendo nel report quante sono
%        "misurate" (poligono) e quante "di default" (linea).
%
%   4) REPORT più organizzato e leggibile:
%      - CSV con colonne più chiare e una seconda tabella di riepilogo
%        per famiglia (GeoScan_Pro_Report_Famiglie.csv).
%      - Pannello testuale della dashboard riorganizzato in sezioni
%        (STENDIMENTO / FAMIGLIE / APERTURA) con spaziatura dinamica.
clear; clc; close all;

% Definizione Percorsi Predefiniti
path_input = 'C:/Users/dario/OneDrive - unifi.it/foto_djiVDA/';
path_output = "E:\RISULTATI_FINALI\rockmass\new\ferret";

% Controllo e creazione automatica della cartella di output se non esiste
if ~exist(path_output, 'dir')
    mkdir(path_output);
end

% ------------------ PARAMETRI CONFIGURABILI ------------------
APERTURA_LINEA_DEFAULT_MM = 2.0;   % apertura convenzionale per le tracce-linea (non poligono)
BIN_SIZE_DEG   = 5;                % passo istogramma orientazioni (dato assiale, 0-180)
MIN_PROM_FRAC  = 0.10;             % prominenza minima picco = frazione del massimo del conteggio
MIN_PEAK_DIST_DEG = 20;            % distanza angolare minima tra due picchi (gradi)
TOLLERANZA_FAMIGLIA_DEG = 30;      % tolleranza +/- per assegnare una discontinuità a una famiglia
% ---------------------------------------------------------------

% 1. CARICAMENTO IMMAGINE
[file, path] = uigetfile({'*.jpg;*.jpeg;*.png;*.tif;*.tiff', 'File Immagine'}, 'Seleziona ortofoto', path_input);
if isequal(file, 0), disp('Operazione annullata dall''utente.'); return; end
img = imread(fullfile(path, file));

% Configurazione Finestra di Lavoro
fig = figure('Name', 'GeoScan Pro - Analisi Strutturale Parete', 'NumberTitle', 'off', 'WindowState', 'maximized');
ax1 = axes('Parent', fig);
imshow(img, 'Parent', ax1, 'InitialMagnification', 'fit');
hold(ax1, 'on');

%% FASE 1: CALIBRAZIONE GSD
title(ax1, 'FASE 1: Calibrazione GSD. Traccia la linea di nota e premi INVIO.');
h_calib = drawline('Color', 'c', 'LineWidth', 2);
pause;
lunghezza_reale_m = str2double(inputdlg('Inserisci la lunghezza REALE della linea (metri):', 'Calibrazione GSD', [1 50], {'1.0'}));
if isnan(lunghezza_reale_m) || lunghezza_reale_m <= 0, lunghezza_reale_m = 1.0; end

% Calcolo GSD (metri per pixel)
pixel_dist = norm(h_calib.Position(2,:) - h_calib.Position(1,:));
GSD = lunghezza_reale_m / pixel_dist;
delete(h_calib);
fprintf('GSD Calcolato: %.6f m/pixel\n', GSD);

%% FASE 2: MAPPATURA DISCONTINUITA' (poli-linee sottili / poligoni per apertura)
title(ax1, ['FASE 2: Traccia ogni discontinuità come linea sottile (poli-linea). ' ...
    'Per marcare anche l''apertura reale, richiudi la traccia su se stessa formando ' ...
    'un piccolo poligono (altrimenti verrà assegnata un''apertura di default). ' ...
    'Doppio click per confermare ogni traccia. ESC/Invio a vuoto per terminare.']);

struttura_fratture = struct('Vertici', {}, 'IsPolygon', {}, 'Lunghezza_m', {}, ...
    'Apertura_mm', {}, 'Apertura_Origine', {}, 'Orientazione_Immagine_deg', {});
contatore = 1;

% Soglia di chiusura: distanza tra primo e ultimo punto, relativa
% all'estensione della traccia, sotto la quale si considera "chiusa"
% (poligono). Soglia sull'area minima per escludere chiusure spurie
% dovute a tracce quasi rettilinee.
SOGLIA_CHIUSURA_REL = 0.15;
SOGLIA_AREA_MIN_PX = 1;

while true
    h_line = drawpolyline('Color', 'y', 'LineWidth', 1);
    pos = h_line.Position;

    if isempty(pos) || size(pos, 1) < 2
        delete(h_line); break;
    end

    % Direzione principale della traccia (analisi delle componenti
    % principali sui vertici), usata sia per l'orientazione sia per la
    % "lunghezza" (estensione lungo la direzione principale, analoga al
    % MajorAxisLength usato in precedenza con regionprops).
    pts_centrati = pos - mean(pos, 1);
    C = cov(pts_centrati);
    if any(~isfinite(C(:)))
        delete(h_line); continue;
    end
    [V, D] = eig(C);
    [~, idx_max] = max(diag(D));
    dir_vec = V(:, idx_max);
    proj = pts_centrati * dir_vec;
    lunghezza_px = max(proj) - min(proj);

    if lunghezza_px < 1
        delete(h_line); continue; % traccia degenere (punto singolo), ignorata
    end

    % Verifica chiusura (poligono) e area racchiusa
    dist_chiusura = norm(pos(1,:) - pos(end,:));
    area_px = 0;
    if size(pos, 1) >= 3
        area_px = abs(polyarea(pos(:,1), pos(:,2)));
    end
    is_poligono = (size(pos, 1) >= 3) && ...
        (dist_chiusura < SOGLIA_CHIUSURA_REL * lunghezza_px) && ...
        (area_px > SOGLIA_AREA_MIN_PX);

    % Orientazione (convenzione pixel immagine, 0-180°, coerente con la
    % convenzione già usata da regionprops Orientation nelle versioni
    % precedenti dello script)
    ang_img = atan2d(dir_vec(2), dir_vec(1));
    if ang_img > 90, ang_img = ang_img - 180; end
    if ang_img <= -90, ang_img = ang_img + 180; end
    if ang_img < 0, ang_img = ang_img + 180; end

    struttura_fratture(contatore).Vertici = pos;
    struttura_fratture(contatore).IsPolygon = is_poligono;
    struttura_fratture(contatore).Lunghezza_m = lunghezza_px * GSD;
    struttura_fratture(contatore).Orientazione_Immagine_deg = ang_img;

    if is_poligono
        % Apertura media = larghezza media del poligono lungo la
        % direzione principale (area / lunghezza), come nelle versioni
        % precedenti basate su area/MajorAxisLength. Questa è
        % un'apertura MISURATA.
        struttura_fratture(contatore).Apertura_mm = (area_px / lunghezza_px) * GSD * 1000;
        struttura_fratture(contatore).Apertura_Origine = 'Misurata (poligono)';
        patch(ax1, pos(:,1), pos(:,2), [1 0.9 0.2], 'FaceAlpha', 0.35, ...
            'EdgeColor', [0.55 0.45 0.10], 'LineWidth', 1);
    else
        % Linea senza spessore: le viene assegnata un'apertura
        % convenzionale di DEFAULT (non più NaN), così da poter essere
        % inclusa nella statistica complessiva dell'apertura.
        struttura_fratture(contatore).Apertura_mm = APERTURA_LINEA_DEFAULT_MM;
        struttura_fratture(contatore).Apertura_Origine = sprintf('Default linea (%.1f mm)', APERTURA_LINEA_DEFAULT_MM);
        plot(ax1, pos(:,1), pos(:,2), 'Color', [0.85 0.75 0.15], 'LineWidth', 0.8);
    end

    delete(h_line);
    contatore = contatore + 1;
end

num_tot_fratture = length(struttura_fratture);
if num_tot_fratture == 0
    errordlg('Nessuna discontinuità tracciata. Calcolo interrotto.', 'Errore'); return;
end

%% FASE 3: FASCIA DI STENDIMENTO E INTERSEZIONI
title(ax1, 'FASE 3: Traccia la LINEA CENTRALE della fascia di stendimento e premi INVIO.');
h_scanline = drawline('Color', 'r', 'LineWidth', 2);
pause;
pos_scanline = h_scanline.Position;
delete(h_scanline);
lunghezza_scanline_m = norm(pos_scanline(2,:) - pos_scanline(1,:)) * GSD;

spessore_fascia_m = str2double(inputdlg('Inserisci lo SPESSORE reale della fascia di stendimento (metri):', ...
    'Fascia di Stendimento', [1 60], {'0.10'}));
if isnan(spessore_fascia_m) || spessore_fascia_m <= 0, spessore_fascia_m = 0.10; end
semi_larghezza_px = (spessore_fascia_m / 2) / GSD;

% Costruzione del rettangolo (fascia) attorno alla linea centrale
dir_scan = (pos_scanline(2,:) - pos_scanline(1,:));
dir_scan = dir_scan / norm(dir_scan);
perp_scan = [-dir_scan(2), dir_scan(1)];
fascia_vertici = [ pos_scanline(1,:) + perp_scan * semi_larghezza_px; ...
                    pos_scanline(2,:) + perp_scan * semi_larghezza_px; ...
                    pos_scanline(2,:) - perp_scan * semi_larghezza_px; ...
                    pos_scanline(1,:) - perp_scan * semi_larghezza_px ];

colore_fascia = [0.70 0.25 0.20];
patch(ax1, fascia_vertici(:,1), fascia_vertici(:,2), colore_fascia, ...
    'FaceAlpha', 0.18, 'EdgeColor', colore_fascia, 'LineStyle', '--', 'LineWidth', 1.3);
plot(ax1, pos_scanline(:,1), pos_scanline(:,2), '--', 'Color', colore_fascia, 'LineWidth', 1);

% Etichette A/B alle due estremità della linea centrale della fascia
text(ax1, pos_scanline(1,1), pos_scanline(1,2), 'A', 'Color', 'w', 'FontWeight', 'bold', ...
    'FontSize', 16, 'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', ...
    'BackgroundColor', colore_fascia, 'Margin', 2);
text(ax1, pos_scanline(2,1), pos_scanline(2,2), 'B', 'Color', 'w', 'FontWeight', 'bold', ...
    'FontSize', 16, 'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', ...
    'BackgroundColor', colore_fascia, 'Margin', 2);

% Intersezione geometrica tra la fascia (rettangolo) e ogni traccia
% (linea aperta o poligono chiuso): si controllano sia gli incroci
% segmento-lato del rettangolo, sia i vertici della traccia che cadono
% dentro la fascia (contenimento). Il punto rappresentativo di intercetta
% è il baricentro dei punti trovati, poi proiettato sulla linea centrale
% per ottenere la progressiva lungo lo stendimento.
intercettate_idx = []; distanze_da_origine = []; punti_intersezione = [];
edges_fascia_idx = [1 2; 2 3; 3 4; 4 1];

for i = 1:num_tot_fratture
    verts = struttura_fratture(i).Vertici;
    n_v = size(verts, 1);

    if struttura_fratture(i).IsPolygon
        edges_idx = [(1:n_v)', [(2:n_v)'; 1]]; % include il lato di chiusura
    else
        edges_idx = [(1:n_v-1)', (2:n_v)'];
    end

    punti_trovati = [];
    for e = 1:size(edges_idx, 1)
        p3 = verts(edges_idx(e,1), :);
        p4 = verts(edges_idx(e,2), :);
        for be = 1:4
            b1 = fascia_vertici(edges_fascia_idx(be,1), :);
            b2 = fascia_vertici(edges_fascia_idx(be,2), :);
            [ok, pt] = segment_intersection(p3, p4, b1, b2);
            if ok
                punti_trovati = [punti_trovati; pt]; %#ok<AGROW>
            end
        end
    end
    % Vertici della traccia contenuti nella fascia (copre il caso di
    % tracce interamente incluse nella fascia, senza incrociarne i lati)
    dentro = inpolygon(verts(:,1), verts(:,2), fascia_vertici(:,1), fascia_vertici(:,2));
    if any(dentro)
        punti_trovati = [punti_trovati; verts(dentro, :)]; %#ok<AGROW>
    end

    if ~isempty(punti_trovati)
        pt_rappresentativo = mean(punti_trovati, 1);
        intercettate_idx = [intercettate_idx; i]; %#ok<AGROW>
        punti_intersezione = [punti_intersezione; pt_rappresentativo]; %#ok<AGROW>
        % Progressiva = proiezione sulla linea centrale della fascia
        dist_px = dot(pt_rappresentativo - pos_scanline(1,:), dir_scan);
        dist_m = dist_px * GSD;
        distanze_da_origine = [distanze_da_origine; dist_m]; %#ok<AGROW>
        plot(ax1, pt_rappresentativo(1), pt_rappresentativo(2), 'ro', 'MarkerSize', 9, ...
            'MarkerFaceColor', 'r', 'LineWidth', 2);
    end
end

%% FASE 4: CALCOLO SPAZIATURA
num_intercettate = length(distanze_da_origine);

if num_intercettate > 0
    [distanze_ordinate, perm_idx] = sort(distanze_da_origine);
    intercettate_idx = intercettate_idx(perm_idx);
    spaziature_apparenti = diff(distanze_ordinate);
    spaziatura_media_m = mean(spaziature_apparenti);
else
    spaziature_apparenti = []; spaziatura_media_m = NaN;
end

%% FASE 5: CLASSIFICAZIONE IN FAMIGLIE (istogramma + ricerca picchi, dato assiale) & APERTURA MEDIA

orientazioni_tot = [struttura_fratture.Orientazione_Immagine_deg]';

[idx_famiglia, picchi_famiglie_deg, ~] = trova_famiglie_picchi( ...
    orientazioni_tot, BIN_SIZE_DEG, MIN_PROM_FRAC, MIN_PEAK_DIST_DEG, TOLLERANZA_FAMIGLIA_DEG);

% idx_famiglia vale 0 per le discontinuità che non rientrano in nessuna
% famiglia entro la tolleranza +/-TOLLERANZA_FAMIGLIA_DEG dal picco più
% vicino ("Non classificata").
max_k = numel(picchi_famiglie_deg);
num_non_classificate = sum(idx_famiglia == 0);

% Orientazione media (statistica circolare) e conteggio di ciascuna
% famiglia effettivamente popolata dai dati (basata sull'assegnazione
% per vicinanza al picco, non sul solo valore del picco)
orientazioni_famiglie = zeros(max_k, 1);
n_famiglie = zeros(max_k, 1);
for k = 1:max_k
    ang_k = orientazioni_tot(idx_famiglia == k);
    n_famiglie(k) = numel(ang_k);
    if isempty(ang_k)
        orientazioni_famiglie(k) = picchi_famiglie_deg(k);
        continue;
    end
    rad_k = deg2rad(ang_k * 2);
    alpha_k = mean(cos(rad_k));
    beta_k  = mean(sin(rad_k));
    ang_fam = rad2deg(atan2(beta_k, alpha_k) / 2);
    if ang_fam < 0, ang_fam = ang_fam + 180; end
    orientazioni_famiglie(k) = ang_fam;
end
fprintf('Famiglie di discontinuità rilevate automaticamente (istogramma+picchi, tolleranza +/-%d°): %d\n', ...
    TOLLERANZA_FAMIGLIA_DEG, max_k);
if num_non_classificate > 0
    fprintf('Discontinuità non classificate (oltre +/-%d° dal picco più vicino): %d\n', ...
        TOLLERANZA_FAMIGLIA_DEG, num_non_classificate);
end

% Apertura media: calcolata ora su TUTTE le discontinuità (poligoni
% misurati + linee con apertura di default), come richiesto.
Apertura_tot = [struttura_fratture.Apertura_mm]';
is_poligono_tot = [struttura_fratture.IsPolygon]';
aperture_misurate = Apertura_tot(is_poligono_tot);
aperture_default  = Apertura_tot(~is_poligono_tot);
num_poligoni_apertura = numel(aperture_misurate);
num_linee_apertura_default = numel(aperture_default);
media_aperture_mm = mean(Apertura_tot);            % media su tutte le discontinuità
media_aperture_misurate_mm = mean(aperture_misurate); % solo poligoni (può essere NaN se 0 poligoni)

%% FASE 6: REPORT CSV
N_frat = (1:num_tot_fratture)';
Lunghezze = [struttura_fratture.Lunghezza_m]';
Orientazioni_Immagine = [struttura_fratture.Orientazione_Immagine_deg]';
Tipo_Traccia = cell(num_tot_fratture, 1);
Apertura_Origine = cell(num_tot_fratture, 1);
for i = 1:num_tot_fratture
    if struttura_fratture(i).IsPolygon
        Tipo_Traccia{i} = 'Poligono';
    else
        Tipo_Traccia{i} = 'Linea';
    end
    Apertura_Origine{i} = struttura_fratture(i).Apertura_Origine;
end
Famiglia_ID = idx_famiglia;
Famiglia_Orientazione_Media_deg = NaN(num_tot_fratture, 1);
mask_classificate = idx_famiglia > 0;
Famiglia_Orientazione_Media_deg(mask_classificate) = orientazioni_famiglie(idx_famiglia(mask_classificate));
Intercettata = cell(num_tot_fratture, 1); Intercettata(:) = {'NO'};
Spaz_Prec_m = NaN(num_tot_fratture, 1); Dist_Prog_m = NaN(num_tot_fratture, 1);

for idx = 1:num_intercettate
    r_idx = intercettate_idx(idx);
    Intercettata{r_idx} = sprintf('SI (%d)', idx);
    Dist_Prog_m(r_idx) = distanze_ordinate(idx);
    if idx > 1, Spaz_Prec_m(r_idx) = spaziature_apparenti(idx-1); end
end

Tabella = table(N_frat, Orientazioni_Immagine, Famiglia_ID, Famiglia_Orientazione_Media_deg, ...
    Tipo_Traccia, Lunghezze, Apertura_tot, Apertura_Origine, Intercettata, Dist_Prog_m, Spaz_Prec_m, ...
    'VariableNames', {'ID', 'Orientazione_Immagine_deg', 'Famiglia_ID', 'Famiglia_Orientazione_Media_deg', ...
    'Tipo_Traccia', 'Lunghezza_m', 'Apertura_mm', 'Apertura_Origine', 'Su_Fascia', 'Dist_Prog_m', 'Spaziatura_m'});
nome_file_csv = fullfile(path_output, 'GeoScan_Pro_Report.csv');
writetable(Tabella, nome_file_csv);

% Tabella di riepilogo per famiglia (più leggibile per un check rapido).
% Se presenti discontinuità non classificate (oltre la tolleranza
% +/-TOLLERANZA_FAMIGLIA_DEG dal picco più vicino), viene aggiunta una
% riga con Famiglia_ID = 0.
Famiglia_ID_riep = (1:max_k)';
Orientazione_Media_deg_riep = orientazioni_famiglie;
N_Discontinuita_riep = n_famiglie;
if num_non_classificate > 0
    Famiglia_ID_riep = [Famiglia_ID_riep; 0];
    Orientazione_Media_deg_riep = [Orientazione_Media_deg_riep; NaN];
    N_Discontinuita_riep = [N_Discontinuita_riep; num_non_classificate];
end
Tabella_Famiglie = table(Famiglia_ID_riep, Orientazione_Media_deg_riep, N_Discontinuita_riep, ...
    'VariableNames', {'Famiglia_ID', 'Orientazione_Media_deg', 'N_Discontinuita'});
nome_file_csv_famiglie = fullfile(path_output, 'GeoScan_Pro_Report_Famiglie.csv');
writetable(Tabella_Famiglie, nome_file_csv_famiglie);

%% FASE 7: DASHBOARD CON IMMAGINE MASSIMIZZATA E REPORT TESTUALE
fig_dash = figure('Name', 'GeoScan Pro - AI Report', 'NumberTitle', 'off', 'Position', [30, 30, 1600, 950]);

% Palette professionale desaturata, in funzione del numero di famiglie
% effettivamente rilevate
hue_vals = mod(linspace(0, 1, max_k + 1), 1); hue_vals(end) = [];
colori_prof = hsv2rgb([hue_vals(:), 0.70*ones(max_k,1), 0.85*ones(max_k,1)]);

% SOTTO-GRAFICO 1: Immagine Grande (tracce colorate per famiglia)
subplot(4, 3, [1, 2, 4, 5, 7, 8, 10, 11]);
imshow(img); hold on;
colore_non_classificata = [0.55 0.55 0.55];
for i = 1:num_tot_fratture
    if idx_famiglia(i) == 0
        colore = colore_non_classificata;
    else
        colore = colori_prof(idx_famiglia(i), :);
    end
    verts = struttura_fratture(i).Vertici;
    if struttura_fratture(i).IsPolygon
        patch(verts(:,1), verts(:,2), colore, 'FaceAlpha', 0.30, 'EdgeColor', colore, 'LineWidth', 1);
    else
        plot(verts(:,1), verts(:,2), 'Color', colore, 'LineWidth', 0.6);
    end
end
patch(fascia_vertici(:,1), fascia_vertici(:,2), colore_fascia, 'FaceAlpha', 0.15, ...
    'EdgeColor', colore_fascia, 'LineStyle', '--', 'LineWidth', 1.2);
text(pos_scanline(1,1), pos_scanline(1,2), 'A', 'Color', 'w', 'FontWeight', 'bold', ...
    'FontSize', 14, 'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', ...
    'BackgroundColor', colore_fascia, 'Margin', 1.5);
text(pos_scanline(2,1), pos_scanline(2,2), 'B', 'Color', 'w', 'FontWeight', 'bold', ...
    'FontSize', 14, 'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', ...
    'BackgroundColor', colore_fascia, 'Margin', 1.5);
if ~isempty(punti_intersezione)
    plot(punti_intersezione(:,1), punti_intersezione(:,2), 'o', 'MarkerSize', 5, ...
        'MarkerFaceColor', colore_fascia, 'MarkerEdgeColor', colore_fascia);
end
title('Discontinuità Mappate per Famiglia', 'FontSize', 14, 'FontWeight', 'bold');

% SOTTO-GRAFICO 2: Rosetta (orientazioni riferite ai pixel immagine)
subplot(4, 3, 3);
polarhistogram(deg2rad([orientazioni_tot; orientazioni_tot + 180]), 36, 'FaceColor', [0.30 0.45 0.55], 'EdgeColor', 'w');
title('Diagramma a Rosetta (rif. immagine)', 'FontSize', 11);
ax_pol = gca; ax_pol.ThetaZeroLocation = 'top'; ax_pol.ThetaDir = 'clockwise';

% SOTTO-GRAFICO 3: Spaziatura - Log-Normale vs Esponenziale negativa (Poisson)
subplot(4, 3, 6);
spaz_valide = spaziature_apparenti(spaziature_apparenti > 0);
if length(spaz_valide) >= 3 && std(spaz_valide) > 0
    histogram(spaz_valide, 'FaceColor', [0.65 0.45 0.42], 'EdgeColor', 'w', 'Normalization', 'pdf', 'DisplayName', 'Dati osservati'); hold on;
    x_spaz = linspace(0, max(spaz_valide)*1.2, 100);

    pd_spaz_ln = fitdist(spaz_valide, 'Lognormal');
    plot(x_spaz, pdf(pd_spaz_ln, x_spaz), '-', 'Color', [0.15 0.15 0.15], 'LineWidth', 1.5, 'DisplayName', 'Log-normale');

    % Modello di processo di Poisson: spaziature attese come esponenziale
    % negativa (Priest & Hudson, 1976), coerente con l'ipotesi di
    % occorrenza casuale e indipendente delle discontinuità lungo lo stendimento.
    pd_spaz_exp = fitdist(spaz_valide, 'Exponential');
    plot(x_spaz, pdf(pd_spaz_exp, x_spaz), '--', 'Color', [0.55 0.30 0.25], 'LineWidth', 1.5, 'DisplayName', 'Esponenziale neg. (Poisson)');

    xlabel('Spaziatura (m)'); ylabel('PDF'); title('Spaziatura: distribuzioni a confronto', 'FontSize', 11); grid on;
    legend('Location', 'best', 'FontSize', 7);
else
    title('Spaziatura (Dati insufficienti)', 'FontSize', 10); axis off;
end

% SOTTO-GRAFICO 4: Apertura - Log-Normale vs Esponenziale negativa (Poisson)
% Calcolata ora su TUTTE le discontinuità (poligoni misurati + linee di default).
subplot(4, 3, 9);
if length(Apertura_tot) >= 3 && std(Apertura_tot) > 0
    histogram(Apertura_tot, 'FaceColor', [0.45 0.55 0.42], 'EdgeColor', 'w', 'Normalization', 'pdf', 'DisplayName', 'Dati osservati'); hold on;
    x_aper = linspace(0, max(Apertura_tot)*1.2, 100);

    pd_aper_ln = fitdist(Apertura_tot, 'Lognormal');
    plot(x_aper, pdf(pd_aper_ln, x_aper), '-', 'Color', [0.15 0.15 0.15], 'LineWidth', 1.5, 'DisplayName', 'Log-normale');

    pd_aper_exp = fitdist(Apertura_tot, 'Exponential');
    plot(x_aper, pdf(pd_aper_exp, x_aper), '--', 'Color', [0.55 0.30 0.25], 'LineWidth', 1.5, 'DisplayName', 'Esponenziale neg. (Poisson)');

    xlabel('Apertura (mm)'); ylabel('PDF'); title('Apertura: distribuzioni a confronto', 'FontSize', 11); grid on;
    legend('Location', 'best', 'FontSize', 7);
else
    title('Apertura (Dati insufficienti)', 'FontSize', 10); axis off;
end

% SOTTO-GRAFICO 5: Report Testuale Dinamico (riorganizzato in sezioni)
subplot(4, 3, 12); axis off;
y = 0.97;
riga = @(dy) y - dy; % helper puramente concettuale (non usato per side effect)

text(0.0, y, '--- REPORT GEOMECCANICO ---', 'FontSize', 12, 'FontWeight', 'bold'); y = y - 0.09;

text(0.0, y, 'STENDIMENTO', 'FontSize', 10, 'FontWeight', 'bold', 'Color', [0.25 0.40 0.50]); y = y - 0.06;
text(0.03, y, sprintf('Lunghezza A-B: %.2f m   |   Spessore fascia: %.2f m', lunghezza_scanline_m, spessore_fascia_m), 'FontSize', 9); y = y - 0.055;
text(0.03, y, sprintf('Discontinuità intercettate: %d ', num_intercettate), 'FontSize', 9); y = y - 0.055;
text(0.03, y, sprintf('Spaziatura media: %.2f m', spaziatura_media_m), 'FontSize', 9); y = y - 0.08;

text(0.0, y, sprintf('FAMIGLIE (rilevate: %d)', max_k), 'FontSize', 10, 'FontWeight', 'bold', 'Color', [0.25 0.40 0.50]); y = y - 0.06;
n_famiglie_da_mostrare = min(max_k, 6);
for k = 1:n_famiglie_da_mostrare
    text(0.03, y, sprintf('F%d: %.1f°   (n=%d)', k, orientazioni_famiglie(k), n_famiglie(k)), 'FontSize', 9);
    y = y - 0.05;
end
if max_k > n_famiglie_da_mostrare
    text(0.03, y, sprintf('... e altre %d famiglie (vedi CSV famiglie)', max_k - n_famiglie_da_mostrare), 'FontSize', 8.5, 'FontAngle', 'italic');
    y = y - 0.05;
end
if num_non_classificate > 0
    text(0.03, y, sprintf('Non classificate (oltre ±%d° dal picco): %d', TOLLERANZA_FAMIGLIA_DEG, num_non_classificate), ...
        'FontSize', 8.5, 'Color', colore_non_classificata, 'FontAngle', 'italic');
    y = y - 0.05;
end
y = y - 0.03;

text(0.0, y, 'APERTURA', 'FontSize', 10, 'FontWeight', 'bold', 'Color', [0.55 0.35 0.15]); y = y - 0.06;
text(0.03, y, sprintf('Media delle discontinuità (n=%d): %.2f mm', num_tot_fratture, media_aperture_mm), 'FontSize', 9); y = y - 0.055;
if num_poligoni_apertura > 0
    text(0.03, y, sprintf('Media di quelle più aperte (n=%d): %.2f mm', num_poligoni_apertura, media_aperture_misurate_mm), 'FontSize', 8.5); y = y - 0.05;
else
    text(0.03, y, 'nessun poligono di apertura tracciato', 'FontSize', 8.5, 'FontAngle', 'italic'); y = y - 0.05;
end
text(0.03, y, sprintf('di cui default su linea (n=%d): %.1f mm', num_linee_apertura_default, APERTURA_LINEA_DEFAULT_MM), 'FontSize', 8.5); y = y - 0.05;

nome_dashboard = fullfile(path_output, 'GeoScan_Pro_Dashboard_AI.png');
saveas(fig_dash, nome_dashboard);
fprintf('>>> Elaborazione completata con successo. File salvati in %s\n', path_output);

%% FUNZIONI AUSILIARIE
function [does_intersect, pt] = segment_intersection(p1, p2, p3, p4)
    % Verifica intersezione tra il segmento p1-p2 e il segmento p3-p4
    % (usata per determinare le intersezioni tra i lati della fascia e le
    % poli-linee/poligoni delle discontinuità)
    x1 = p1(1); y1 = p1(2); x2 = p2(1); y2 = p2(2);
    x3 = p3(1); y3 = p3(2); x4 = p4(1); y4 = p4(2);

    denom = (x1 - x2) * (y3 - y4) - (y1 - y2) * (x3 - x4);
    does_intersect = false; pt = [NaN, NaN];

    if abs(denom) < 1e-10
        return; % segmenti paralleli o coincidenti
    end

    t = ((x1 - x3) * (y3 - y4) - (y1 - y3) * (x3 - x4)) / denom;
    u = -((x1 - x2) * (y1 - y3) - (y1 - y2) * (x1 - x3)) / denom;

    if t >= 0 && t <= 1 && u >= 0 && u <= 1
        does_intersect = true;
        pt = [x1 + t * (x2 - x1), y1 + t * (y2 - y1)];
    end
end

function [idx_membership, peak_angles, peak_counts] = trova_famiglie_picchi(theta_deg, binSizeDeg, minPromFrac, minDistDeg, tolleranzaDeg)
    % Riconoscimento automatico delle famiglie di discontinuità come
    % dato ASSIALE (periodicità 180°) tramite istogramma + ricerca dei
    % picchi. Implementazione manuale (massimi locali + prominenza +
    % soppressione dei picchi troppo vicini), che NON richiede il
    % Signal Processing Toolbox (nessun uso di findpeaks).
    %
    % Le orientazioni vengono ricondotte in [0,180) e l'istogramma viene
    % "triplicato" circolarmente (centri-180, centri, centri+180) in
    % modo da individuare correttamente anche i picchi vicini al bordo
    % 0°/180°. Ogni misura viene poi assegnata alla famiglia il cui
    % picco è più vicino in senso circolare (distanza mod 180°), ma
    % SOLO se questa distanza è <= tolleranzaDeg (es. 30°): altrimenti
    % la discontinuità resta "Non classificata" (idx_membership = 0).
    theta_mod = mod(theta_deg, 180);

    edges = 0:binSizeDeg:180;
    counts = histcounts(theta_mod, edges);
    centers = edges(1:end-1) + binSizeDeg/2;

    counts_ext = [counts, counts, counts];
    centers_ext = [centers - 180, centers, centers + 180];

    minPeakProminence = max(1, max(counts) * minPromFrac);
    minPeakDistSamples = max(1, round(minDistDeg / binSizeDeg));

    peak_angles = [];
    if any(counts > 0)
        cand_idx = trova_massimi_locali(counts_ext);
        if ~isempty(cand_idx)
            prom_vals = arrayfun(@(ii) calcola_prominenza(counts_ext, ii), cand_idx);
            cand_idx = cand_idx(prom_vals >= minPeakProminence);
        end
        if ~isempty(cand_idx)
            % Soppressione dei picchi troppo vicini: si procede dal più
            % alto al più basso, mantenendo un picco solo se rispetta la
            % distanza minima (in campioni) da quelli già selezionati.
            [~, ord] = sort(counts_ext(cand_idx), 'descend');
            cand_ord = cand_idx(ord);
            selezionati = [];
            for ii = 1:numel(cand_ord)
                c = cand_ord(ii);
                if isempty(selezionati) || all(abs(selezionati - c) >= minPeakDistSamples)
                    selezionati(end+1) = c; %#ok<AGROW>
                end
            end
            peak_centers = centers_ext(selezionati);
            keep = peak_centers >= 0 & peak_centers < 180;
            peak_angles = sort(peak_centers(keep))';
        end
    end

    if isempty(peak_angles)
        % Fallback: nessun picco robusto individuato -> un'unica famiglia
        % definita dalla media circolare di tutti i dati.
        rad = deg2rad(theta_mod * 2);
        alpha = mean(cos(rad)); beta = mean(sin(rad));
        ang_media = rad2deg(atan2(beta, alpha) / 2);
        if ang_media < 0, ang_media = ang_media + 180; end
        peak_angles = ang_media;
    end

    peak_angles = sort(peak_angles);
    n = numel(theta_mod);
    k = numel(peak_angles);
    idx_membership = zeros(n, 1); % 0 = non classificata (default)
    for i = 1:n
        % distanza circolare in dominio mod 180
        d = abs(mod(theta_mod(i) - peak_angles + 90, 180) - 90);
        [dmin, imin] = min(d);
        if dmin <= tolleranzaDeg
            idx_membership(i) = imin;
        end
        % altrimenti resta 0 (non classificata): oltre +/-tolleranzaDeg
        % dal picco più vicino
    end
    peak_counts = arrayfun(@(kk) sum(idx_membership == kk), 1:k)';
end

function idx = trova_massimi_locali(y)
    % Indici dei massimi locali di un vettore (bordi esclusi): un
    % campione è massimo locale se è strettamente maggiore del
    % precedente e maggiore o uguale al successivo (gestisce i plateau
    % prendendone il primo campione).
    n = numel(y);
    idx = [];
    for i = 2:n-1
        if y(i) > y(i-1) && y(i) >= y(i+1)
            idx(end+1) = i; %#ok<AGROW>
        end
    end
end

function p = calcola_prominenza(y, i)
    % Prominenza topografica "manuale" del campione i: altezza del picco
    % rispetto al più alto tra i due "punti di sella" più vicini (a
    % sinistra e a destra) oltre i quali si incontra un valore >= y(i).
    % Se non si incontra un valore maggiore prima del bordo del vettore,
    % si usa il minimo osservato fino al bordo.
    n = numel(y);

    left_min = y(i);
    j = i - 1;
    while j >= 1 && y(j) < y(i)
        left_min = min(left_min, y(j));
        j = j - 1;
    end

    right_min = y(i);
    k = i + 1;
    while k <= n && y(k) < y(i)
        right_min = min(right_min, y(k));
        k = k + 1;
    end

    p = y(i) - max(left_min, right_min);
end