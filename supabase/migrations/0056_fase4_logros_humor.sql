-- 0056 · Fase 4: 150 logros, avisos con humor (y la FAQ, que vive en la app)
--  · Logros: 30 familias × 5 niveles (Bronce, Plata, Oro, Diamante, Leyenda). Cada familia mide una cifra del jugador
--    (goles, rachas, porra, Fantasy…) y cada nivel es un umbral. Los de la categoría «humor» son ocultos hasta conseguirlos.
--  · Los logros antiguos se conservan (primer_gol → goles_1, hat_trick → noche_3, manita → noche_5; el resto ya coincide).
--  · Se revisan al cerrar cada partido (todos los miembros activos) y cada hora (fichajes, porra…).
--  · Avisos con humor: el título de los avisos habituales se cambia por una frase con gracia en el idioma de cada uno.
--    Cada jugador (Perfil) y cada liga (Ajustes) pueden desactivarlo. El cuerpo del aviso sigue con la información.

alter table perfiles add column if not exists avisos_humor boolean not null default true;
alter table ligas add column if not exists avisos_humor boolean not null default true;

create table if not exists logros_catalogo (
  codigo    text primary key,
  familia   text not null,
  categoria text not null,
  emoji     text not null,
  nivel     smallint not null check (nivel between 1 and 5),
  umbral    numeric not null,
  orden     int not null,
  oculto    boolean not null default false
);
create table if not exists logros_familias_txt (
  familia     text not null,
  idioma      text not null,
  nombre      text not null,
  descripcion text not null,
  primary key (familia, idioma)
);
create table if not exists logros_niveles_txt (
  nivel  smallint not null,
  idioma text not null,
  nombre text not null,
  primary key (nivel, idioma)
);
create table if not exists frases_humor (
  tipo   text not null,
  idioma text not null,
  n      smallint not null,
  texto  text not null,
  primary key (tipo, idioma, n)
);
alter table logros_catalogo enable row level security;
alter table logros_familias_txt enable row level security;
alter table logros_niveles_txt enable row level security;
alter table frases_humor enable row level security;
revoke all on logros_catalogo, logros_familias_txt, logros_niveles_txt, frases_humor from anon, authenticated;


-- Códigos antiguos → nuevos
update logros set tipo = 'goles_1' where tipo = 'primer_gol';
update logros set tipo = 'noche_3' where tipo = 'hat_trick';
update logros set tipo = 'noche_5' where tipo = 'manita';

create temp table _fam (o int, familia text, categoria text, emoji text, umbrales numeric[], nombres text[], descs text[]);
insert into _fam values
(1, 'goles', 'ataque', '⚽', array[1, 10, 25, 50, 100], array['Pichichi de barrio', 'Pichichi de barri', 'Pichichi do barrio', 'Auzoko Pichichi', 'Local Golden Boot', 'Torschützenkönig im Viertel', 'Capocannoniere di quartiere', 'Topscorer van de buurt', 'Buteur du quartier'], array['Goles marcados', 'Gols marcats', 'Goles marcados', 'Sartutako golak', 'Goals scored', 'Erzielte Tore', 'Gol segnati', 'Gemaakte doelpunten', 'Buts marqués']),
(2, 'asist', 'ataque', '🎯', array[1, 10, 25, 50, 100], array['Socio ideal', 'Soci ideal', 'Socio ideal', 'Bikote ezin hobea', 'Perfect partner', 'Der perfekte Partner', 'Compagno ideale', 'Ideale aangever', 'Partenaire idéal'], array['Asistencias', 'Assistències', 'Asistencias', 'Gol-paseak', 'Assists', 'Vorlagen', 'Assist', 'Assists', 'Passes décisives']),
(3, 'noche', 'ataque', '🎩', array[2, 3, 4, 5, 7], array['Noche mágica', 'Nit màgica', 'Noite máxica', 'Gau magikoa', 'Magic night', 'Magische Nacht', 'Notte magica', 'Magische avond', 'Soirée magique'], array['Goles en un solo partido', 'Gols en un sol partit', 'Goles nun só partido', 'Partida bakarrean golak', 'Goals in a single match', 'Tore in einem Spiel', 'Gol in una sola partita', 'Doelpunten in één wedstrijd', 'Buts en un seul match']),
(4, 'olfato', 'ataque', '👃', array[2, 3, 5, 7, 10], array['Olfato de gol', 'Olfacte de gol', 'Olfacto de gol', 'Gol-usaina', 'Nose for goal', 'Torriecher', 'Fiuto del gol', 'Neus voor de goal', 'Flair du buteur'], array['Partidos seguidos marcando', 'Partits seguits marcant', 'Partidos seguidos marcando', 'Gola sartuz jarraian partidak', 'Matches in a row scoring', 'Spiele in Folge mit Tor', 'Partite di fila a segno', 'Wedstrijden op rij gescoord', 'Matchs d''affilée en marquant']),
(5, 'partidazo', 'ataque', '💥', array[15, 20, 25, 30, 40], array['Partidazo', 'Partidàs', 'Partidazo', 'Partida ikaragarria', 'Match of the season', 'Gala-Auftritt', 'Partitone', 'Topwedstrijd', 'Match de légende'], array['Puntos Fantasy en un partido', 'Punts Fantasy en un partit', 'Puntos Fantasy nun partido', 'Fantasy puntuak partida batean', 'Fantasy points in one match', 'Fantasy-Punkte in einem Spiel', 'Punti Fantasy in una partita', 'Fantasy-punten in één wedstrijd', 'Points Fantasy en un match']),
(6, 'muro', 'porteria', '🧱', array[1, 5, 10, 25, 50], array['El Muro', 'El Mur', 'O Muro', 'Harresia', 'The Wall', 'Die Mauer', 'Il Muro', 'De Muur', 'Le Mur'], array['Porterías a cero', 'Porteries a zero', 'Porterías a cero', 'Atea hutsean', 'Clean sheets', 'Zu-null-Spiele', 'Porte inviolate', 'Keer de nul', 'Clean sheets']),
(7, 'paradas', 'porteria', '🧤', array[5, 25, 50, 100, 250], array['Manos de santo', 'Mans de sant', 'Mans de santo', 'Esku santuak', 'Safe hands', 'Fliegende Hände', 'Mani d''oro', 'Gouden handen', 'Mains en or'], array['Paradas clave', 'Aturades clau', 'Paradas clave', 'Geldiketa garrantzitsuak', 'Key saves', 'Wichtige Paraden', 'Parate decisive', 'Belangrijke reddingen', 'Arrêts décisifs']),
(8, 'penparados', 'porteria', '🦸', array[1, 3, 5, 10, 20], array['Superhéroe del penalti', 'Superheroi del penal', 'Superheroe do penalti', 'Penaltiko superheroia', 'Penalty superhero', 'Elfmeterkiller', 'Supereroe dei rigori', 'Penaltykiller', 'Super-héros des penaltys'], array['Penaltis parados', 'Penals aturats', 'Penaltis parados', 'Geldiarazitako penaltiak', 'Penalties saved', 'Gehaltene Elfmeter', 'Rigori parati', 'Gestopte penalty''s', 'Penaltys arrêtés']),
(9, 'partidos', 'constancia', '👟', array[10, 25, 50, 100, 200], array['Fijo en la convocatoria', 'Fix a la convocatòria', 'Fixo na convocatoria', 'Deialdian beti', 'Squad regular', 'Stammspieler', 'Fisso in rosa', 'Vaste waarde', 'Toujours convoqué'], array['Partidos jugados', 'Partits jugats', 'Partidos xogados', 'Jokatutako partidak', 'Matches played', 'Gespielte Spiele', 'Partite giocate', 'Gespeelde wedstrijden', 'Matchs joués']),
(10, 'racha', 'constancia', '🔥', array[5, 10, 20, 30, 50], array['Nunca falla', 'Mai falla', 'Nunca falla', 'Inoiz ez du huts egiten', 'Never misses', 'Immer dabei', 'Mai assente', 'Altijd van de partij', 'Jamais absent'], array['Partidos de la liga seguidos sin faltar', 'Partits de la lliga seguits sense faltar', 'Partidos da liga seguidos sen faltar', 'Ligako partidak jarraian huts egin gabe', 'League matches in a row without missing one', 'Ligaspiele in Folge ohne Fehlen', 'Partite di lega di fila senza mancare', 'Competitiewedstrijden op rij aanwezig', 'Matchs de la ligue d''affilée sans manquer']),
(11, 'madrugador', 'constancia', '⏰', array[1, 5, 15, 30, 60], array['Madrugador', 'Matiner', 'Madrugador', 'Goiztiarra', 'Early bird', 'Frühaufsteher', 'Mattiniero', 'Vroege vogel', 'Lève-tôt'], array['Veces el primero en apuntarse', 'Vegades el primer a apuntar-se', 'Veces o primeiro en apuntarse', 'Lehena izena ematen', 'Times first to sign up', 'Als Erster angemeldet', 'Volte primo a iscriversi', 'Keer als eerste aangemeld', 'Fois premier inscrit']),
(12, 'victorias', 'resultados', '🏆', array[5, 25, 50, 100, 200], array['Ganador nato', 'Guanyador nat', 'Gañador nato', 'Jaiotzez irabazlea', 'Born winner', 'Geborener Sieger', 'Vincente nato', 'Geboren winnaar', 'Gagnant né'], array['Victorias', 'Victòries', 'Vitorias', 'Garaipenak', 'Wins', 'Siege', 'Vittorie', 'Overwinningen', 'Victoires']),
(13, 'invicto', 'resultados', '🛡️', array[3, 5, 10, 15, 20], array['Invicto', 'Invicte', 'Invicto', 'Garaitu gabea', 'Unbeaten', 'Ungeschlagen', 'Imbattuto', 'Ongeslagen', 'Invaincu'], array['Partidos seguidos sin perder', 'Partits seguits sense perdre', 'Partidos seguidos sen perder', 'Galdu gabe jarraian partidak', 'Matches in a row unbeaten', 'Spiele in Folge ungeschlagen', 'Partite di fila senza perdere', 'Wedstrijden op rij ongeslagen', 'Matchs d''affilée sans perdre']),
(14, 'imparable', 'resultados', '🚀', array[3, 5, 7, 10, 15], array['Imparable', 'Imparable', 'Imparable', 'Geldiezina', 'Unstoppable', 'Unaufhaltsam', 'Inarrestabile', 'Onstuitbaar', 'Inarrêtable'], array['Victorias seguidas', 'Victòries seguides', 'Vitorias seguidas', 'Garaipenak jarraian', 'Wins in a row', 'Siege in Folge', 'Vittorie di fila', 'Overwinningen op rij', 'Victoires d''affilée']),
(15, 'mvp', 'reconocimiento', '⭐', array[1, 5, 10, 25, 50], array['Estrella del partido', 'Estrella del partit', 'Estrela do partido', 'Partidako izarra', 'Star of the match', 'Spieler des Spiels', 'Stella della partita', 'Ster van de wedstrijd', 'Étoile du match'], array['Veces MVP', 'Vegades MVP', 'Veces MVP', 'MVP aldiz', 'Times MVP', 'Mal MVP', 'Volte MVP', 'Keer MVP', 'Fois MVP']),
(16, 'podio', 'reconocimiento', '🥉', array[1, 5, 15, 30, 60], array['Siempre en el podio', 'Sempre al podi', 'Sempre no podio', 'Beti podiumean', 'Always on the podium', 'Immer auf dem Podest', 'Sempre sul podio', 'Altijd op het podium', 'Toujours sur le podium'], array['Veces entre los 3 mejores del partido', 'Vegades entre els 3 millors del partit', 'Veces entre os 3 mellores do partido', 'Partidako 3 onenen artean', 'Times in the match''s top 3', 'Mal unter den besten 3 des Spiels', 'Volte tra i 3 migliori della partita', 'Keer bij de beste 3 van de wedstrijd', 'Fois dans le top 3 du match']),
(17, 'nota', 'reconocimiento', '📈', array[1, 5, 15, 30, 60], array['Matrícula de honor', 'Matrícula d''honor', 'Matrícula de honra', 'Ohorezko matrikula', 'Top marks', 'Bestnote', 'Lode', 'Met lof', 'Mention très bien'], array['Partidos con nota media de 8 o más', 'Partits amb nota mitjana de 8 o més', 'Partidos con nota media de 8 ou máis', '8ko batez bestekoa edo gehiago duten partidak', 'Matches rated 8 or higher', 'Spiele mit Note 8 oder besser', 'Partite con media voto 8 o più', 'Wedstrijden met een 8 of hoger', 'Matchs notés 8 ou plus']),
(18, 'juez', 'reconocimiento', '🗳️', array[5, 15, 30, 60, 100], array['Juez imparcial', 'Jutge imparcial', 'Xuíz imparcial', 'Epaile inpartziala', 'Fair judge', 'Gerechter Richter', 'Giudice imparziale', 'Eerlijke jury', 'Juge impartial'], array['Post-partidos votados', 'Post-partits votats', 'Post-partidos votados', 'Bozkatutako partida ostekoak', 'Post-match votes cast', 'Abgegebene Bewertungen', 'Post-partita votati', 'Nabesprekingen gestemd', 'Après-matchs votés']),
(19, 'vitrina', 'reconocimiento', '🏅', array[1, 3, 5, 10, 20], array['Vitrina llena', 'Vitrina plena', 'Vitrina chea', 'Erakusleiho betea', 'Full trophy cabinet', 'Volle Vitrine', 'Bacheca piena', 'Volle prijzenkast', 'Vitrine pleine'], array['Premios de temporada', 'Premis de temporada', 'Premios de tempada', 'Denboraldiko sariak', 'Season awards', 'Saisonauszeichnungen', 'Premi stagionali', 'Seizoensprijzen', 'Trophées de saison']),
(20, 'autogol', 'humor', '🙈', array[1, 3, 5, 10, 20], array['Fichaje del rival', 'Fitxatge del rival', 'Fichaxe do rival', 'Aurkariaren fitxaketa', 'Signed by the rivals', 'Bester Mann des Gegners', 'Acquisto degli avversari', 'Aanwinst van de tegenstander', 'Recrue de l''adversaire'], array['Goles en propia puerta', 'Gols en pròpia porta', 'Goles en propia porta', 'Norberaren atean golak', 'Own goals', 'Eigentore', 'Autogol', 'Eigen doelpunten', 'Buts contre son camp']),
(21, 'penfallo', 'humor', '🤡', array[1, 3, 5, 8, 12], array['Panenka fallida', 'Panenka fallida', 'Panenka fallida', 'Panenka hutsa', 'Failed Panenka', 'Missglückter Panenka', 'Cucchiaio fallito', 'Mislukte panenka', 'Panenka ratée'], array['Penaltis fallados', 'Penals fallats', 'Penaltis fallados', 'Huts egindako penaltiak', 'Penalties missed', 'Verschossene Elfmeter', 'Rigori sbagliati', 'Gemiste penalty''s', 'Penaltys ratés']),
(22, 'derrotas', 'humor', '😭', array[5, 15, 30, 60, 100], array['Mártir del fútbol', 'Màrtir del futbol', 'Mártir do fútbol', 'Futboleko martiria', 'Football martyr', 'Fußball-Märtyrer', 'Martire del calcio', 'Voetbalmartelaar', 'Martyr du foot'], array['Derrotas', 'Derrotes', 'Derrotas', 'Porrotak', 'Defeats', 'Niederlagen', 'Sconfitte', 'Nederlagen', 'Défaites']),
(23, 'gafe', 'humor', '🐈‍⬛', array[3, 5, 7, 10, 15], array['Gafe oficial', 'Gafe oficial', 'Gafe oficial', 'Zorigaiztoko ofiziala', 'Official jinx', 'Offizieller Pechvogel', 'Iettatore ufficiale', 'Officiële pechvogel', 'Chat noir officiel'], array['Derrotas seguidas', 'Derrotes seguides', 'Derrotas seguidas', 'Porrotak jarraian', 'Defeats in a row', 'Niederlagen in Folge', 'Sconfitte di fila', 'Nederlagen op rij', 'Défaites d''affilée']),
(24, 'sequia', 'humor', '🏜️', array[10, 20, 30, 50, 75], array['Sequía histórica', 'Sequera històrica', 'Seca histórica', 'Lehorte historikoa', 'Historic drought', 'Historische Torflaute', 'Siccità storica', 'Historische droogte', 'Sécheresse historique'], array['Partidos seguidos sin marcar', 'Partits seguits sense marcar', 'Partidos seguidos sen marcar', 'Gola sartu gabe jarraian partidak', 'Matches in a row without scoring', 'Spiele in Folge ohne Tor', 'Partite di fila senza segnare', 'Wedstrijden op rij zonder doelpunt', 'Matchs d''affilée sans marquer']),
(25, 'mister', 'fantasy', '🧠', array[1, 3, 10, 25, 50], array['Míster de la jornada', 'Míster de la jornada', 'Míster da xornada', 'Jardunaldiko misterra', 'Manager of the round', 'Trainer des Spieltags', 'Mister della giornata', 'Coach van de speelronde', 'Coach de la journée'], array['Jornadas ganadas como mánager', 'Jornades guanyades com a mànager', 'Xornadas gañadas como mánager', 'Mánager gisa irabazitako jardunaldiak', 'Rounds won as manager', 'Spieltage als Manager gewonnen', 'Giornate vinte da manager', 'Speelrondes gewonnen als manager', 'Journées gagnées comme manager']),
(26, 'fichajes', 'fantasy', '📝', array[1, 10, 25, 50, 100], array['Director deportivo', 'Director esportiu', 'Director deportivo', 'Kirol zuzendaria', 'Sporting director', 'Sportdirektor', 'Direttore sportivo', 'Technisch directeur', 'Directeur sportif'], array['Fichajes', 'Fitxatges', 'Fichaxes', 'Fitxaketak', 'Signings', 'Transfers', 'Acquisti', 'Aankopen', 'Recrues']),
(27, 'clausulazo', 'fantasy', '💰', array[1, 3, 5, 10, 20], array['Clausulazo', 'Clausulàs', 'Clausulazo', 'Klausula-kolpea', 'Release clause raid', 'Klausel-Coup', 'Colpo di clausola', 'Clausulestunt', 'Coup de la clause'], array['Cláusulas pagadas', 'Clàusules pagades', 'Cláusulas pagadas', 'Ordaindutako klausulak', 'Release clauses paid', 'Bezahlte Ausstiegsklauseln', 'Clausole pagate', 'Betaalde clausules', 'Clauses payées']),
(28, 'ventas', 'fantasy', '🦈', array[1, 10, 25, 50, 100], array['Tiburón del mercado', 'Tauró del mercat', 'Tiburón do mercado', 'Merkatuko marrazoa', 'Market shark', 'Transferhai', 'Squalo del mercato', 'Transferhaai', 'Requin du mercato'], array['Ventas', 'Vendes', 'Vendas', 'Salmentak', 'Sales', 'Verkäufe', 'Cessioni', 'Verkopen', 'Ventes']),
(29, 'pitoniso', 'porra', '🔮', array[1, 5, 15, 30, 60], array['Pitoniso', 'Endeví', 'Adiviño', 'Igarlea', 'Fortune teller', 'Hellseher', 'Indovino', 'Waarzegger', 'Devin'], array['Boletos de porra acertados', 'Butlletes de porra encertades', 'Boletos de porra acertados', 'Asmatutako porra-txartelak', 'Winning prediction slips', 'Gewonnene Tippscheine', 'Schedine vinte', 'Gewonnen voorspellingen', 'Pronostics gagnés']),
(30, 'suerte', 'porra', '🍀', array[3, 5, 10, 20, 50], array['Golpe de suerte', 'Cop de sort', 'Golpe de sorte', 'Zorte kolpea', 'Lucky strike', 'Glückstreffer', 'Colpo di fortuna', 'Geluksworp', 'Coup de chance'], array['Cuota del mejor boleto acertado', 'Quota de la millor butlleta encertada', 'Cota do mellor boleto acertado', 'Asmatutako txartel onenaren kuota', 'Best winning odds', 'Beste gewonnene Quote', 'Quota della miglior schedina vinta', 'Hoogste gewonnen quotering', 'Meilleure cote gagnée']);
create temp table _niv (nivel int, nombres text[]);
insert into _niv values
(1, array['Bronce', 'Bronze', 'Bronce', 'Brontzea', 'Bronze', 'Bronze', 'Bronzo', 'Brons', 'Bronze']),
(2, array['Plata', 'Plata', 'Prata', 'Zilarra', 'Silver', 'Silber', 'Argento', 'Zilver', 'Argent']),
(3, array['Oro', 'Or', 'Ouro', 'Urrea', 'Gold', 'Gold', 'Oro', 'Goud', 'Or']),
(4, array['Diamante', 'Diamant', 'Diamante', 'Diamantea', 'Diamond', 'Diamant', 'Diamante', 'Diamant', 'Diamant']),
(5, array['Leyenda', 'Llegenda', 'Lenda', 'Kondaira', 'Legend', 'Legende', 'Leggenda', 'Legende', 'Légende']);
create temp table _idi as
  select * from unnest(array['es', 'ca', 'gl', 'eu', 'en', 'de', 'it', 'nl', 'fr']) with ordinality i(idioma, n);
insert into logros_catalogo (codigo, familia, categoria, emoji, nivel, umbral, orden, oculto)
select f.familia || '_' || u.umbral, f.familia, f.categoria, f.emoji, u.n, u.umbral, (f.o - 1) * 5 + u.n, f.categoria = 'humor'
  from _fam f cross join unnest(f.umbrales) with ordinality u(umbral, n)
on conflict (codigo) do update set familia = excluded.familia, categoria = excluded.categoria, emoji = excluded.emoji,
  nivel = excluded.nivel, umbral = excluded.umbral, orden = excluded.orden, oculto = excluded.oculto;
insert into logros_familias_txt (familia, idioma, nombre, descripcion)
select f.familia, i.idioma, f.nombres[i.n], f.descs[i.n] from _fam f cross join _idi i
on conflict (familia, idioma) do update set nombre = excluded.nombre, descripcion = excluded.descripcion;
insert into logros_niveles_txt (nivel, idioma, nombre)
select v.nivel, i.idioma, v.nombres[i.n] from _niv v cross join _idi i
on conflict (nivel, idioma) do update set nombre = excluded.nombre;
-- Avisos de logro: «Familia · Nivel» en castellano → en cada idioma
insert into logros_traducciones (es, idioma, texto)
select f.nombres[1] || ' · ' || v.nombres[1], i.idioma, f.nombres[i.n] || ' · ' || v.nombres[i.n]
  from _fam f cross join _niv v cross join _idi i where i.idioma <> 'es'
on conflict (es, idioma) do update set texto = excluded.texto;
create temp table _fr (tipo text, n int, textos text[]);
insert into _fr values
('puntos', 1, array['🏆 Ya hay puntos. Que empiecen las excusas', '🏆 Ja hi ha punts. Que comencin les excuses', '🏆 Xa hai puntos. Que comecen as escusas', '🏆 Puntuak badaude. Has daitezela aitzakiak', '🏆 Points are in. Let the excuses begin', '🏆 Die Punkte sind da. Die Ausreden können beginnen', '🏆 Punti pronti. Che inizino le scuse', '🏆 De punten zijn binnen. Laat de excuses maar komen', '🏆 Les points sont là. Place aux excuses']),
('puntos', 2, array['🏆 Puntos publicados: hora de presumir (o de esconderse)', '🏆 Punts publicats: hora de presumir (o d''amagar-se)', '🏆 Puntos publicados: hora de presumir (ou de agocharse)', '🏆 Puntuak argitaratuta: harrotzeko (edo ezkutatzeko) ordua', '🏆 Points published: time to brag (or hide)', '🏆 Punkte veröffentlicht: Zeit zum Angeben (oder Verstecken)', '🏆 Punti pubblicati: ora di vantarsi (o nascondersi)', '🏆 Punten gepubliceerd: tijd om op te scheppen (of te verstoppen)', '🏆 Points publiés : l''heure de frimer (ou de se cacher)']),
('puntos', 3, array['🏆 El VAR ha hablado: puntos publicados', '🏆 El VAR ha parlat: punts publicats', '🏆 O VAR falou: puntos publicados', '🏆 VARrak hitz egin du: puntuak argitaratuta', '🏆 VAR has spoken: points are out', '🏆 Der VAR hat entschieden: Punkte sind da', '🏆 Il VAR ha parlato: punti pubblicati', '🏆 De VAR heeft gesproken: punten zijn binnen', '🏆 La VAR a parlé : points publiés']),
('recordatorio_convocatoria', 1, array['⚽ Las botas no se ponen solas: convocatoria abierta', '⚽ Les botes no es posen soles: convocatòria oberta', '⚽ As botas non se poñen soas: convocatoria aberta', '⚽ Botak ez dira bakarrik jartzen: deialdia irekita', '⚽ Boots don''t lace themselves: sign-up is open', '⚽ Die Schuhe binden sich nicht selbst: Anmeldung offen', '⚽ Gli scarpini non si allacciano da soli: convocazione aperta', '⚽ Je schoenen strikken zichzelf niet: aanmelden kan', '⚽ Les crampons ne se lacent pas tout seuls : inscriptions ouvertes']),
('recordatorio_convocatoria', 2, array['⚽ Se buscan valientes (y algún portero)', '⚽ Es busquen valents (i algun porter)', '⚽ Búscanse valentes (e algún porteiro)', '⚽ Ausartak behar dira (eta atezainen bat)', '⚽ Brave souls wanted (and maybe a keeper)', '⚽ Mutige gesucht (und vielleicht ein Torwart)', '⚽ Cercasi coraggiosi (e magari un portiere)', '⚽ Dappere spelers gezocht (en misschien een keeper)', '⚽ On cherche des courageux (et peut-être un gardien)']),
('recordatorio_convocatoria', 3, array['⚽ El sofá puede esperar: ¡apúntate!', '⚽ El sofà pot esperar: apunta''t!', '⚽ O sofá pode agardar: apúntate!', '⚽ Sofak itxaron dezake: eman izena!', '⚽ The sofa can wait: sign up!', '⚽ Das Sofa kann warten: meld dich an!', '⚽ Il divano può aspettare: iscriviti!', '⚽ De bank kan wachten: meld je aan!', '⚽ Le canapé peut attendre : inscris-toi !']),
('post_partido', 1, array['📝 Hora de juzgar a tus compañeros (con cariño)', '📝 Hora de jutjar els companys (amb estima)', '📝 Hora de xulgar aos compañeiros (con agarimo)', '📝 Lagunak epaitzeko ordua (maitasunez)', '📝 Time to judge your teammates (lovingly)', '📝 Zeit, deine Mitspieler zu bewerten (liebevoll)', '📝 È ora di giudicare i compagni (con affetto)', '📝 Tijd om je teamgenoten te beoordelen (met liefde)', '📝 L''heure de juger tes coéquipiers (avec tendresse)']),
('post_partido', 2, array['📝 El post-partido te espera. Sé justo… o no', '📝 El post-partit t''espera. Sigues just… o no', '📝 O post-partido agárdate. Sé xusto… ou non', '📝 Partida ostekoa zure zain. Izan zuzena… edo ez', '📝 The post-match awaits. Be fair… or not', '📝 Die Nachbereitung wartet. Sei fair… oder nicht', '📝 Il post-partita ti aspetta. Sii giusto… o no', '📝 De nabespreking wacht. Wees eerlijk… of niet', '📝 L''après-match t''attend. Sois juste… ou pas']),
('post_partido', 3, array['📝 ¿Quién la lió y quién la rompió? Vota', '📝 Qui la va liar i qui la va petar? Vota', '📝 Quen a liou e quen a rompeu? Vota', '📝 Nork izorratu zuen eta nork distiratu? Bozkatu', '📝 Who messed up and who shone? Vote', '📝 Wer hat''s verbockt, wer hat geglänzt? Abstimmen', '📝 Chi ha combinato guai e chi ha brillato? Vota', '📝 Wie verprutste het en wie blonk uit? Stem', '📝 Qui a raté et qui a brillé ? Vote']),
('equipos', 1, array['✅ Equipos hechos. Ya puedes empezar a quejarte', '✅ Equips fets. Ja pots començar a queixar-te', '✅ Equipos feitos. Xa podes comezar a queixarte', '✅ Taldeak eginda. Kexatzen has zaitezke', '✅ Teams are set. You may now start complaining', '✅ Teams stehen. Ab jetzt darf gemeckert werden', '✅ Squadre fatte. Ora puoi iniziare a lamentarti', '✅ De teams staan. Je mag nu gaan klagen', '✅ Équipes faites. Tu peux commencer à râler']),
('equipos', 2, array['✅ El algoritmo ha hablado: equipos hechos', '✅ L''algoritme ha parlat: equips fets', '✅ O algoritmo falou: equipos feitos', '✅ Algoritmoak hitz egin du: taldeak eginda', '✅ The algorithm has spoken: teams are set', '✅ Der Algorithmus hat entschieden: Teams stehen', '✅ L''algoritmo ha parlato: squadre fatte', '✅ Het algoritme heeft gesproken: teams staan', '✅ L''algorithme a parlé : équipes faites']),
('equipos', 3, array['✅ Equipos listos. ¿Desequilibrados? Imposible', '✅ Equips a punt. Desequilibrats? Impossible', '✅ Equipos listos. Desequilibrados? Imposible', '✅ Taldeak prest. Desorekatuak? Ezinezkoa', '✅ Teams ready. Unbalanced? Impossible', '✅ Teams fertig. Unausgeglichen? Unmöglich', '✅ Squadre pronte. Squilibrate? Impossibile', '✅ Teams klaar. Ongelijk? Onmogelijk', '✅ Équipes prêtes. Déséquilibrées ? Impossible']),
('recordatorio_alineacion', 1, array['🧠 Tu alineación está más vacía que la grada', '🧠 La teva alineació està més buida que la grada', '🧠 A túa aliñación está máis baleira cá bancada', '🧠 Zure hamaikakoa harmailak baino hutsago dago', '🧠 Your line-up is emptier than the stands', '🧠 Deine Aufstellung ist leerer als die Tribüne', '🧠 La tua formazione è più vuota degli spalti', '🧠 Je opstelling is leger dan de tribune', '🧠 Ta compo est plus vide que les tribunes']),
('recordatorio_alineacion', 2, array['🧠 Míster, ¿y la alineación?', '🧠 Míster, i l''alineació?', '🧠 Míster, e a aliñación?', '🧠 Mister, eta hamaikakoa?', '🧠 Coach, where''s the line-up?', '🧠 Trainer, wo bleibt die Aufstellung?', '🧠 Mister, e la formazione?', '🧠 Coach, waar blijft de opstelling?', '🧠 Coach, et la compo ?']),
('recordatorio_alineacion', 3, array['🧠 Sin alineación no hay gloria. Revísala', '🧠 Sense alineació no hi ha glòria. Revisa-la', '🧠 Sen aliñación non hai gloria. Revísaa', '🧠 Hamaikakorik gabe ez dago aintzarik. Berrikusi', '🧠 No line-up, no glory. Check it', '🧠 Ohne Aufstellung kein Ruhm. Prüf sie', '🧠 Senza formazione niente gloria. Controllala', '🧠 Geen opstelling, geen glorie. Kijk ernaar', '🧠 Pas de compo, pas de gloire. Vérifie-la']),
('recordatorio_votar', 1, array['⏳ Último aviso: tus compañeros esperan tu veredicto', '⏳ Últim avís: els companys esperen el teu veredicte', '⏳ Último aviso: os compañeiros agardan o teu veredicto', '⏳ Azken abisua: lagunak zure epaiaren zain', '⏳ Last call: your teammates await your verdict', '⏳ Letzter Aufruf: deine Mitspieler warten auf dein Urteil', '⏳ Ultima chiamata: i compagni aspettano il tuo verdetto', '⏳ Laatste oproep: je teamgenoten wachten op je oordeel', '⏳ Dernier appel : tes coéquipiers attendent ton verdict']),
('recordatorio_votar', 2, array['⏳ Se cierra el post-partido. No dejes que voten por ti', '⏳ Es tanca el post-partit. No deixis que votin per tu', '⏳ Péchase o post-partido. Non deixes que voten por ti', '⏳ Partida ostekoa ixten ari da. Ez utzi zure ordez bozkatzen', '⏳ Post-match is closing. Don''t let others vote for you', '⏳ Die Nachbereitung schließt. Lass nicht andere für dich abstimmen', '⏳ Il post-partita sta chiudendo. Non lasciar votare gli altri per te', '⏳ De nabespreking sluit. Laat anderen niet voor je stemmen', '⏳ L''après-match ferme. Ne laisse pas les autres voter pour toi']),
('recordatorio_votar', 3, array['⏳ Último minuto de descuento para votar', '⏳ Últim minut de descompte per votar', '⏳ Último minuto de desconto para votar', '⏳ Bozkatzeko luzapeneko azken minutua', '⏳ Final minute of stoppage time to vote', '⏳ Letzte Minute Nachspielzeit zum Abstimmen', '⏳ Ultimo minuto di recupero per votare', '⏳ Laatste minuut blessuretijd om te stemmen', '⏳ Dernière minute de temps additionnel pour voter']),
('cancelado', 1, array['🌧️ Partido cancelado. Las agujetas tendrán que esperar', '🌧️ Partit cancel·lat. Les agulletes hauran d''esperar', '🌧️ Partido cancelado. As agullas terán que agardar', '🌧️ Partida bertan behera. Agujetek itxaron beharko dute', '🌧️ Match cancelled. The muscle aches will have to wait', '🌧️ Spiel abgesagt. Der Muskelkater muss warten', '🌧️ Partita annullata. I dolori muscolari dovranno aspettare', '🌧️ Wedstrijd afgelast. De spierpijn moet wachten', '🌧️ Match annulé. Les courbatures attendront']),
('cancelado', 2, array['🌧️ Se suspende el partido. Tu rodilla te lo agradece', '🌧️ Se suspèn el partit. El teu genoll t''ho agraeix', '🌧️ Suspéndese o partido. O teu xeonllo agradéceche', '🌧️ Partida eten da. Zure belaunak eskertzen dizu', '🌧️ Match called off. Your knee says thanks', '🌧️ Spiel fällt aus. Dein Knie sagt danke', '🌧️ Partita sospesa. Il tuo ginocchio ringrazia', '🌧️ Wedstrijd gaat niet door. Je knie zegt dank je', '🌧️ Match annulé. Ton genou te remercie']),
('cancelado', 3, array['🌧️ Partido cancelado: hoy gana el sofá', '🌧️ Partit cancel·lat: avui guanya el sofà', '🌧️ Partido cancelado: hoxe gaña o sofá', '🌧️ Partida bertan behera: gaur sofak irabazten du', '🌧️ Match cancelled: the sofa wins today', '🌧️ Spiel abgesagt: heute gewinnt das Sofa', '🌧️ Partita annullata: oggi vince il divano', '🌧️ Wedstrijd afgelast: vandaag wint de bank', '🌧️ Match annulé : aujourd''hui, le canapé gagne']),
('entras', 1, array['✅ ¡Entras! Calienta, que sales de titular', '✅ Hi entres! Escalfa, que surts de titular', '✅ Entras! Quenta, que saes de titular', '✅ Barruan zaude! Berotu, titular ateratzen zara', '✅ You''re in! Warm up, you''re starting', '✅ Du bist dabei! Wärm dich auf, du spielst von Anfang an', '✅ Sei dentro! Scaldati, parti titolare', '✅ Je bent erbij! Warm op, je staat in de basis', '✅ Tu es pris ! Échauffe-toi, tu es titulaire']),
('entras', 2, array['✅ Plaza conseguida. Ahora no te lesiones antes', '✅ Plaça aconseguida. Ara no et lesionis abans', '✅ Praza conseguida. Agora non te lesiones antes', '✅ Plaza lortuta. Orain ez zaitez lehenago lesionatu', '✅ Spot secured. Now don''t get injured before kick-off', '✅ Platz sicher. Jetzt bloß nicht vorher verletzen', '✅ Posto conquistato. Ora non infortunarti prima', '✅ Plek binnen. Raak nu niet vooraf geblesseerd', '✅ Place obtenue. Ne te blesse pas avant']),
('entras', 3, array['✅ Estás dentro. Que no se te olviden las botas', '✅ Ets dins. Que no se t''oblidin les botes', '✅ Estás dentro. Que non se che esquezan as botas', '✅ Barruan zaude. Ez ahaztu botak', '✅ You''re in. Don''t forget your boots', '✅ Du bist dabei. Vergiss die Schuhe nicht', '✅ Sei dentro. Non dimenticare gli scarpini', '✅ Je bent erbij. Vergeet je schoenen niet', '✅ Tu es dedans. N''oublie pas tes crampons']),
('capitan', 1, array['©️ Eres capitán: elige bien, que luego te lo recordarán', '©️ Ets capità: tria bé, que després t''ho recordaran', '©️ Es capitán: escolle ben, que despois lembraranche', '©️ Kapitaina zara: ondo aukeratu, gero gogoraraziko dizute', '©️ You''re captain: choose wisely, they''ll remind you later', '©️ Du bist Kapitän: wähle gut, sie werden dich daran erinnern', '©️ Sei capitano: scegli bene, te lo ricorderanno', '©️ Je bent aanvoerder: kies goed, ze herinneren je eraan', '©️ Tu es capitaine : choisis bien, on te le rappellera']),
('capitan', 2, array['©️ Brazalete para ti. Un gran poder conlleva…', '©️ Braçal per a tu. Un gran poder comporta…', '©️ Brazalete para ti. Un gran poder leva…', '©️ Besokoa zuretzat. Botere handiak dakar…', '©️ The armband is yours. With great power…', '©️ Die Binde gehört dir. Aus großer Macht folgt…', '©️ La fascia è tua. Da grandi poteri…', '©️ De band is voor jou. Met grote kracht…', '©️ Le brassard est à toi. Un grand pouvoir implique…']),
('capitan', 3, array['©️ Capitán: tu momento de hacer el equipo de tus sueños', '©️ Capità: el teu moment de fer l''equip dels teus somnis', '©️ Capitán: o teu momento de facer o equipo dos teus soños', '©️ Kapitaina: zure ametsetako taldea egiteko unea', '©️ Captain: time to build your dream team', '©️ Kapitän: Zeit für dein Traumteam', '©️ Capitano: è il momento della squadra dei tuoi sogni', '©️ Aanvoerder: tijd voor je droomteam', '©️ Capitaine : l''heure de ton équipe de rêve']),
('deuda', 1, array['💸 Tu cuenta pendiente ya tiene más minutos que tú', '💸 El teu deute ja té més minuts que tu', '💸 A túa débeda xa ten máis minutos ca ti', '💸 Zure zorrak zuk baino minutu gehiago ditu', '💸 Your unpaid bill has more minutes than you', '💸 Deine offene Rechnung hat mehr Spielminuten als du', '💸 Il tuo debito ha più minuti di te', '💸 Je openstaande rekening heeft meer speelminuten dan jij', '💸 Ta dette a plus de temps de jeu que toi']),
('deuda', 2, array['💸 El tesorero te manda saludos (y la cuenta)', '💸 El tresorer et saluda (i et passa el compte)', '💸 O tesoureiro mándache saúdos (e a conta)', '💸 Diruzainak agurrak bidaltzen dizkizu (eta kontua)', '💸 The treasurer says hi (and sends the bill)', '💸 Der Kassenwart grüßt (und schickt die Rechnung)', '💸 Il tesoriere ti saluta (e ti manda il conto)', '💸 De penningmeester doet de groeten (en stuurt de rekening)', '💸 Le trésorier te salue (et t''envoie l''addition)']),
('deuda', 3, array['💸 Pagar también es jugar en equipo', '💸 Pagar també és jugar en equip', '💸 Pagar tamén é xogar en equipo', '💸 Ordaintzea ere talde-jokoa da', '💸 Paying up is teamwork too', '💸 Bezahlen ist auch Teamwork', '💸 Anche pagare è gioco di squadra', '💸 Betalen is ook teamwork', '💸 Payer, c''est aussi jouer collectif']),
('clausula', 1, array['💰 Te han pagado la cláusula. Duele, pero cobras', '💰 T''han pagat la clàusula. Fa mal, però cobres', '💰 Pagáronche a cláusula. Doe, pero cobras', '💰 Klausula ordaindu dizute. Min ematen du, baina kobratzen duzu', '💰 Your release clause was paid. It hurts, but you get paid', '💰 Deine Klausel wurde gezahlt. Tut weh, bringt aber Geld', '💰 Ti hanno pagato la clausola. Fa male, ma incassi', '💰 Je clausule is betaald. Het doet pijn, maar je cashet', '💰 On a payé ta clause. Ça fait mal, mais tu encaisses']),
('clausula', 2, array['💰 Clausulazo: te roban un jugador, pero no gratis', '💰 Clausulàs: et roben un jugador, però no gratis', '💰 Clausulazo: róubanche un xogador, pero non de balde', '💰 Klausula-kolpea: jokalari bat lapurtu dizute, baina ez doan', '💰 Clause raid: they took your player, but not for free', '💰 Klausel-Coup: Spieler weg, aber nicht umsonst', '💰 Colpo di clausola: ti rubano un giocatore, ma non gratis', '💰 Clausulestunt: speler weg, maar niet gratis', '💰 Coup de la clause : on te vole un joueur, mais pas gratuitement']),
('clausula', 3, array['💰 Alguien ha roto la hucha por tu jugador', '💰 Algú ha trencat la guardiola pel teu jugador', '💰 Alguén rompeu a hucha polo teu xogador', '💰 Norbaitek itsulapikoa hautsi du zure jokalariagatik', '💰 Someone broke the piggy bank for your player', '💰 Jemand hat für deinen Spieler das Sparschwein geschlachtet', '💰 Qualcuno ha rotto il salvadanaio per il tuo giocatore', '💰 Iemand heeft het spaarvarken gebroken voor jouw speler', '💰 Quelqu''un a cassé sa tirelire pour ton joueur']),
('cambio_hora', 1, array['🕒 Cambio de hora. Reajusta la siesta', '🕒 Canvi d''hora. Reajusta la migdiada', '🕒 Cambio de hora. Axusta a sesta', '🕒 Ordu aldaketa. Doitu siesta', '🕒 Time change. Readjust your nap', '🕒 Neue Uhrzeit. Mittagsschlaf anpassen', '🕒 Cambio d''orario. Riorganizza il pisolino', '🕒 Nieuwe tijd. Pas je middagdutje aan', '🕒 Changement d''horaire. Réajuste ta sieste']),
('cambio_hora', 2, array['🕒 Nueva hora para el partido: que no te pille el VAR', '🕒 Nova hora per al partit: que no t''enxampi el VAR', '🕒 Nova hora para o partido: que non te colla o VAR', '🕒 Partidarako ordu berria: VARrak harrapa ez zaitzan', '🕒 New kick-off time: don''t let VAR catch you out', '🕒 Neue Anstoßzeit: lass dich nicht vom VAR erwischen', '🕒 Nuovo orario: non farti beccare dal VAR', '🕒 Nieuwe aftraptijd: laat je niet verrassen door de VAR', '🕒 Nouvel horaire : ne te fais pas piéger par la VAR']),
('cambio_hora', 3, array['🕒 El partido se mueve. Tú también deberías', '🕒 El partit es mou. Tu també hauries de fer-ho', '🕒 O partido móvese. Ti tamén deberías', '🕒 Partida mugitzen da. Zuk ere egin beharko zenuke', '🕒 The match has moved. So should you', '🕒 Das Spiel wurde verschoben. Du solltest dich auch bewegen', '🕒 La partita si sposta. Anche tu dovresti', '🕒 De wedstrijd verschuift. Jij ook', '🕒 Le match bouge. Toi aussi, tu devrais']),
('subasta', 1, array['🔨 Subasta abierta: saca la cartera, mánager', '🔨 Subhasta oberta: treu la cartera, mànager', '🔨 Poxa aberta: saca a carteira, mánager', '🔨 Enkantea irekita: atera zorroa, mánager', '🔨 Auction open: get your wallet out, manager', '🔨 Auktion offen: Geldbeutel raus, Manager', '🔨 Asta aperta: tira fuori il portafoglio, manager', '🔨 Veiling open: trek je portemonnee, manager', '🔨 Enchères ouvertes : sors le portefeuille, manager']),
('subasta', 2, array['🔨 Hay jugadores en el escaparate. ¿Pujas o miras?', '🔨 Hi ha jugadors a l''aparador. Puges o mires?', '🔨 Hai xogadores no escaparate. Poxas ou miras?', '🔨 Jokalariak erakusleihoan. Eskaintzen duzu ala begiratzen?', '🔨 Players in the shop window. Bid or browse?', '🔨 Spieler im Schaufenster. Bieten oder gucken?', '🔨 Giocatori in vetrina. Offri o guardi?', '🔨 Spelers in de etalage. Bieden of kijken?', '🔨 Des joueurs en vitrine. Tu enchéris ou tu regardes ?']),
('subasta', 3, array['🔨 Martillo listo: empieza la subasta', '🔨 Martell a punt: comença la subhasta', '🔨 Martelo listo: comeza a poxa', '🔨 Mailua prest: enkantea hasten da', '🔨 Gavel ready: the auction begins', '🔨 Hammer bereit: die Auktion beginnt', '🔨 Martelletto pronto: inizia l''asta', '🔨 Hamer klaar: de veiling begint', '🔨 Marteau prêt : les enchères commencent']),
('oferta', 1, array['🤝 Te han hecho una oferta. Hazte el interesante', '🤝 T''han fet una oferta. Fes-te l''interessant', '🤝 Fixéronche unha oferta. Faite o interesante', '🤝 Eskaintza bat egin dizute. Egin interesgarriarena', '🤝 You''ve got an offer. Play hard to get', '🤝 Du hast ein Angebot. Spiel den Unnahbaren', '🤝 Hai ricevuto un''offerta. Fatti desiderare', '🤝 Je hebt een bod. Speel het spel maar', '🤝 Tu as reçu une offre. Fais-toi désirer']),
('oferta', 2, array['🤝 Ojeadores rondando a tu jugador', '🤝 Ullejadors rondant el teu jugador', '🤝 Cazatalentos arredor do teu xogador', '🤝 Talentu-ehiztariak zure jokalariaren inguruan', '🤝 Scouts are circling your player', '🤝 Scouts umkreisen deinen Spieler', '🤝 Osservatori attorno al tuo giocatore', '🤝 Scouts cirkelen rond je speler', '🤝 Des recruteurs tournent autour de ton joueur']),
('oferta', 3, array['🤝 Oferta en la mesa. ¿Vendes o subes el precio?', '🤝 Oferta sobre la taula. Vens o puges el preu?', '🤝 Oferta na mesa. Vendes ou subes o prezo?', '🤝 Eskaintza mahai gainean. Saldu ala prezioa igo?', '🤝 Offer on the table. Sell or raise the price?', '🤝 Angebot auf dem Tisch. Verkaufen oder Preis hochtreiben?', '🤝 Offerta sul tavolo. Vendi o alzi il prezzo?', '🤝 Bod op tafel. Verkopen of de prijs opdrijven?', '🤝 Offre sur la table. Tu vends ou tu fais monter les prix ?']);
insert into frases_humor (tipo, idioma, n, texto)
select r.tipo, i.idioma, r.n, r.textos[i.n] from _fr r cross join _idi i
on conflict (tipo, idioma, n) do update set texto = excluded.texto;
drop table _fam, _niv, _idi, _fr;


-- ───────────── Métricas de cada jugador ─────────────
-- Racha más larga de «true» seguidos
create or replace function _max_racha(p boolean[]) returns int
language plpgsql immutable as $$
declare x boolean; c int := 0; m int := 0;
begin
  if p is null then return 0; end if;
  foreach x in array p loop
    if coalesce(x, false) then c := c + 1; if c > m then m := c; end if; else c := 0; end if;
  end loop;
  return m;
end $$;

-- Una cifra por familia de logros (las claves coinciden con logros_catalogo.familia)
create or replace function metricas_logros(p_miembro uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_liga uuid; r record; a record; s record; v_racha int; v_juez int; v_vit int; v_mister int;
        t record; ap record; v_madr int;
begin
  select liga_id into v_liga from miembros where id = p_miembro;
  select coalesce(sum(partidos), 0) partidos, coalesce(sum(goles), 0) goles, coalesce(sum(asistencias), 0) asist,
         coalesce(sum(mvps), 0) mvp, coalesce(sum(victorias), 0) victorias, coalesce(sum(derrotas), 0) derrotas
    into r from v_rendimiento where miembro_id = p_miembro;
  select coalesce(sum(aj.porterias_cero), 0) muro, coalesce(sum(aj.paradas_clave), 0) paradas,
         coalesce(sum(aj.penaltis_parados), 0) penparados, coalesce(sum(aj.autogoles), 0) autogol,
         coalesce(sum(aj.penaltis_fallados), 0) penfallo, coalesce(max(aj.goles), 0) noche
    into a from acta_jugador aj join partidos pa on pa.id = aj.partido_id
   where aj.miembro_id = p_miembro and pa.estado = 'cerrado';
  select coalesce(max(pf.total), 0) partidazo,
         count(*) filter (where pf.puesto between 1 and 3) podio,
         count(*) filter (where pf.nota_media >= 8) nota,
         _max_racha(array_agg(pf.derrotas = 0 order by pa.fecha_hora)) invicto,
         _max_racha(array_agg(pf.victorias > pf.derrotas order by pa.fecha_hora)) imparable,
         _max_racha(array_agg(pf.derrotas > pf.victorias order by pa.fecha_hora)) gafe,
         _max_racha(array_agg(coalesce(aj.goles, 0) > 0 order by pa.fecha_hora)) olfato,
         _max_racha(array_agg(coalesce(aj.goles, 0) = 0 order by pa.fecha_hora)) sequia
    into s
    from puntos_fantasy pf join partidos pa on pa.id = pf.partido_id
    left join acta_jugador aj on aj.partido_id = pf.partido_id and aj.miembro_id = pf.miembro_id
   where pf.miembro_id = p_miembro and pa.estado = 'cerrado';
  select _max_racha(array_agg(exists (select 1 from puntos_fantasy x where x.partido_id = pa.id and x.miembro_id = p_miembro)
                              order by pa.fecha_hora))
    into v_racha from partidos pa where pa.liga_id = v_liga and pa.estado = 'cerrado';
  select count(*) into v_juez from (
    select partido_id from votos_mvp where votante_id = p_miembro
    union select partido_id from valoraciones where votante_id = p_miembro
    union select partido_id from votos_podio where votante_id = p_miembro) x;
  select count(*) into v_vit from premios where miembro_id = p_miembro;
  select count(*) into v_mister from puntos_manager pm
   where pm.manager_id = p_miembro and pm.puntos > 0
     and pm.puntos = (select max(x.puntos) from puntos_manager x where x.partido_id = pm.partido_id);
  select count(*) filter (where tipo in ('compra', 'subasta', 'draft', 'clausula_pagada', 'oferta_pagada')) fichajes,
         count(*) filter (where tipo = 'clausula_pagada') clausulazo,
         count(*) filter (where tipo in ('venta', 'oferta_cobrada')) ventas
    into t from transacciones_fantasy where manager_id = p_miembro;
  select count(*) filter (where estado = 'ganada') pitoniso,
         coalesce(max(cuota_total) filter (where estado = 'ganada'), 0) suerte
    into ap from apuestas where miembro_id = p_miembro;
  select count(*) into v_madr from convocatorias c join partidos pa on pa.id = c.partido_id
   where c.miembro_id = p_miembro and pa.estado = 'cerrado' and c.estado = 'confirmado'
     and not exists (select 1 from convocatorias o where o.partido_id = c.partido_id and o.miembro_id <> c.miembro_id
                       and o.inscrito_en <= c.inscrito_en);

  return jsonb_build_object(
    'goles', r.goles, 'asist', r.asist, 'noche', a.noche, 'olfato', s.olfato, 'partidazo', s.partidazo,
    'muro', a.muro, 'paradas', a.paradas, 'penparados', a.penparados,
    'partidos', r.partidos, 'racha', coalesce(v_racha, 0), 'madrugador', v_madr,
    'victorias', r.victorias, 'invicto', s.invicto, 'imparable', s.imparable,
    'mvp', r.mvp, 'podio', s.podio, 'nota', s.nota, 'juez', v_juez, 'vitrina', v_vit,
    'autogol', a.autogol, 'penfallo', a.penfallo, 'derrotas', r.derrotas, 'gafe', s.gafe, 'sequia', s.sequia,
    'mister', v_mister, 'fichajes', t.fichajes, 'clausulazo', t.clausulazo, 'ventas', t.ventas,
    'pitoniso', ap.pitoniso, 'suerte', ap.suerte);
end $$;
revoke execute on function metricas_logros(uuid) from public, anon, authenticated;

-- Nombre completo en castellano («Pichichi de barrio · Oro»); los avisos lo traducen con logros_traducciones
create or replace function nombre_logro(p_tipo text) returns text
language sql stable set search_path = public as $$
  select coalesce((select f.nombre || ' · ' || n.nombre
                     from logros_catalogo c
                     join logros_familias_txt f on f.familia = c.familia and f.idioma = 'es'
                     join logros_niveles_txt n on n.nivel = c.nivel and n.idioma = 'es'
                    where c.codigo = p_tipo), p_tipo) $$;

-- Evalúa los 150 logros de un jugador. Avisa solo del nivel más alto conseguido de cada familia.
create or replace function evaluar_logros(p_miembro uuid, p_partido uuid) returns int
language plpgsql security definer set search_path = public as $$
declare v_liga uuid; m jsonb; c record; n int; k int := 0; v_nuevos text[] := '{}'; v_grupo boolean; v_nombre text;
begin
  select liga_id into v_liga from miembros where id = p_miembro;
  if v_liga is null then return 0; end if;
  m := metricas_logros(p_miembro);
  for c in select * from logros_catalogo where coalesce((m ->> familia)::numeric, 0) >= umbral order by orden loop
    insert into logros (liga_id, miembro_id, tipo, partido_id) values (v_liga, p_miembro, c.codigo, p_partido)
    on conflict (miembro_id, tipo) do nothing;
    get diagnostics n = row_count;
    if n > 0 then k := k + 1; v_nuevos := v_nuevos || c.codigo; end if;
  end loop;
  if k > 0 and coalesce(current_setting('ff.sin_avisos', true), '') <> '1' then
    for c in select distinct on (familia) * from logros_catalogo where codigo = any (v_nuevos) order by familia, nivel desc loop
      v_nombre := nombre_logro(c.codigo);
      v_grupo := c.nivel >= 4 or (c.categoria = 'humor' and c.nivel >= 2);
      perform notificar(case when v_grupo
                          then (select coalesce(array_agg(perfil_id), '{}') from miembros where liga_id = v_liga and estado = 'activo')
                          else array[(select perfil_id from miembros where id = p_miembro)] end,
                        v_liga, 'logro', '🏅 ' || v_nombre,
                        case when v_grupo then nombre_miembro(p_miembro) || ' consigue «' || v_nombre || '»'
                             else '¡Nuevo logro: ' || v_nombre || '!' end,
                        '/logros/' || p_miembro);
    end loop;
  end if;
  return k;
end $$;
revoke execute on function evaluar_logros(uuid, uuid) from public, anon, authenticated;

-- Los 150 logros de un jugador, con su progreso, en el idioma pedido
create or replace function logros_de(p_miembro uuid, p_idioma text default 'es') returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_liga uuid; m jsonb; v_idi text; v_activos int;
begin
  select liga_id into v_liga from miembros where id = p_miembro;
  if v_liga is null or not es_miembro(v_liga) then raise exception 'No perteneces a esta liga'; end if;
  v_idi := case when p_idioma in ('es', 'ca', 'gl', 'eu', 'en', 'de', 'it', 'nl', 'fr') then p_idioma else 'es' end;
  m := metricas_logros(p_miembro);
  select greatest(count(*), 1) into v_activos from miembros where liga_id = v_liga and estado = 'activo';
  return jsonb_build_object(
    'total', (select count(*) from logros_catalogo),
    'conseguidos', (select count(*) from logros l join logros_catalogo c on c.codigo = l.tipo where l.miembro_id = p_miembro),
    'logros', (select jsonb_agg(jsonb_build_object(
                 'codigo', c.codigo, 'familia', c.familia, 'categoria', c.categoria, 'emoji', c.emoji, 'nivel', c.nivel,
                 'umbral', c.umbral, 'oculto', c.oculto,
                 'nombre', f.nombre, 'nivel_nombre', nv.nombre, 'descripcion', f.descripcion || ': ' || c.umbral,
                 'valor', coalesce((m ->> c.familia)::numeric, 0),
                 'conseguido_en', l.conseguido_en,
                 'pct', round(100.0 * (select count(*) from logros x join miembros mm on mm.id = x.miembro_id
                                        where x.tipo = c.codigo and mm.liga_id = v_liga and mm.estado = 'activo') / v_activos))
               order by c.orden)
                 from logros_catalogo c
                 join logros_familias_txt f on f.familia = c.familia and f.idioma = v_idi
                 join logros_niveles_txt nv on nv.nivel = c.nivel and nv.idioma = v_idi
                 left join logros l on l.miembro_id = p_miembro and l.tipo = c.codigo));
end $$;
revoke execute on function logros_de(uuid, text) from public, anon;
grant execute on function logros_de(uuid, text) to authenticated;

-- Al cerrar un partido: logros de todos los miembros activos (también mánagers y porra).
-- El disparador se llama z_… para ir después de la jornada Fantasy y de la porra (orden alfabético).
create or replace function logros_al_cerrar() returns trigger
language plpgsql security definer set search_path = public as $$
declare r record;
begin
  for r in select id from miembros where liga_id = new.liga_id and estado = 'activo' loop
    perform evaluar_logros(r.id, new.id);
  end loop;
  return null;
end $$;
drop trigger if exists logros_al_cerrar on partidos;
drop trigger if exists z_logros_al_cerrar on partidos;
create trigger z_logros_al_cerrar after update of estado on partidos
  for each row when (new.estado = 'cerrado' and old.estado is distinct from 'cerrado')
  execute function logros_al_cerrar();

-- Cada hora: ligas con movimiento reciente (fichajes, porra, partidos)
create or replace function revisar_logros() returns int
language plpgsql security definer set search_path = public as $$
declare r record; k int := 0;
begin
  for r in select m.id from miembros m
            where m.estado = 'activo'
              and m.liga_id in (select liga_id from partidos where fecha_hora between now() - interval '3 days' and now()
                                union select liga_id from transacciones_fantasy where creado_en > now() - interval '2 hours'
                                union select liga_id from apuestas where liquidada_en > now() - interval '2 hours') loop
    k := k + evaluar_logros(r.id, null);
  end loop;
  return k;
end $$;
revoke execute on function revisar_logros() from public, anon, authenticated;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('ff_logros', '17 * * * *', 'select public.revisar_logros()');
  end if;
end $$;

-- ───────────── Avisos con humor ─────────────
-- Si el jugador y la liga lo permiten y el tipo de aviso tiene frases, el título es una frase al azar en su idioma.
-- Si el aviso no tenía cuerpo, el título serio pasa al cuerpo para no perder información.
create or replace function notificar(p_perfiles uuid[], p_liga uuid, p_tipo text, p_titulo text, p_cuerpo text,
                                     p_ruta text default null) returns int
language plpgsql security definer set search_path = public as $$
declare k int; v_liga_humor boolean;
begin
  v_liga_humor := coalesce((select avisos_humor from ligas where id = p_liga), true)
                  and coalesce(current_setting('ff.sin_humor', true), '') <> '1';
  insert into notificaciones (perfil_id, liga_id, tipo, titulo, cuerpo, ruta)
  select d.u, p_liga, p_tipo,
         coalesce(x.frase, traducir_aviso(p_titulo, coalesce(pf.idioma, 'es'))),
         case when x.frase is not null and coalesce(p_cuerpo, '') = ''
              then traducir_aviso(p_titulo, coalesce(pf.idioma, 'es'))
              else traducir_aviso(coalesce(p_cuerpo, ''), coalesce(pf.idioma, 'es')) end,
         p_ruta
    from (select distinct u from unnest(p_perfiles) u where u is not null) d
    left join perfiles pf on pf.id = d.u
    cross join lateral (
      select case when v_liga_humor and coalesce(pf.avisos_humor, true)
                  then (select fh.texto from frases_humor fh
                         where fh.tipo = p_tipo and fh.idioma = coalesce(pf.idioma, 'es')
                         order by random() limit 1) end as frase) x;
  get diagnostics k = row_count;
  return k;
end $$;

-- ───────────── Reparto: alineación completa siempre (arreglo de la Fase 2) ─────────────
create or replace function repartir_equipo(p_liga uuid, p_manager uuid) returns int
language plpgsql security definer set search_path = public as $$
declare l ligas; v_r int; v_obj numeric; v_cand uuid[]; v_fic uuid[]; v_precio numeric[]; v_inv boolean[]; v_n int;
        v_mejor int[]; v_mejor_dif numeric := null; v_sel int[]; v_suma numeric; v_ninv int; i int; t int;
        k int := 0; v_ya int; v_saldo numeric; v_total numeric := 0;
begin
  select * into l from ligas where id = p_liga;
  select count(*) into v_ya from fichas where liga_id = p_liga and propietario_id = p_manager;
  v_r := least(l.jugadores_por_equipo, l.max_plantilla) - v_ya;   -- alineación completa
  if v_r <= 0 then return 0; end if;
  select saldo into v_saldo from fantasy_managers where liga_id = p_liga and miembro_id = p_manager;

  select array_agg(jugador), array_agg(ficha), array_agg(precio), array_agg(no_habitual)
    into v_cand, v_fic, v_precio, v_inv
    from (select mj.miembro_id jugador, ficha_libre(p_liga, mj.miembro_id) ficha,
                 precio_ficha(ficha_libre(p_liga, mj.miembro_id)) precio, mj.no_habitual
            from mercado_jugador mj
           where mj.liga_id = p_liga and mj.miembro_id in (select jugadores_liga(p_liga))
             and ficha_libre(p_liga, mj.miembro_id) is not null
             and (l.auto_fichaje or mj.miembro_id <> p_manager)
             and not exists (select 1 from fichas f where f.propietario_id = p_manager and f.jugador_id = mj.miembro_id)
           order by random()) x;
  v_n := coalesce(array_length(v_cand, 1), 0);
  if v_n = 0 then return 0; end if;
  v_r := least(v_r, v_n);
  -- objetivo: el valor medio × huecos, sin pasar del presupuesto (deja un 4 % de margen)
  select avg(p) * v_r into v_obj from unnest(v_precio) p;
  v_obj := least(v_obj, v_saldo * 0.96);

  for t in 1..400 loop
    select array_agg(x) into v_sel from (select x from generate_series(1, v_n) x order by random() limit v_r) s;
    v_suma := 0; v_ninv := 0;
    foreach i in array v_sel loop
      v_suma := v_suma + v_precio[i];
      if v_inv[i] then v_ninv := v_ninv + 1; end if;
    end loop;
    continue when v_ninv > 1 or v_suma > v_saldo;
    if v_mejor_dif is null or abs(v_suma - v_obj) < v_mejor_dif then
      v_mejor_dif := abs(v_suma - v_obj);
      v_mejor := v_sel;
      exit when v_mejor_dif < l.valor_base * 0.02;
    end if;
  end loop;
  -- Si ninguna combinación cabe (precios inflados por rareza y escasez), los más baratos: siempre alineación completa.
  if v_mejor is null then
    select array_agg(x order by p) into v_mejor
      from (select x, v_precio[x] p from generate_series(1, v_n) x
             order by (v_inv[x] and x <> (select y from generate_series(1, v_n) y where v_inv[y] order by v_precio[y] limit 1)),
                      v_precio[x]
             limit v_r) s;
  end if;
  if v_mejor is null then return 0; end if;

  foreach i in array v_mejor loop
    perform transferir_ficha(v_fic[i], p_manager, v_precio[i]);
    v_total := v_total + v_precio[i];
    k := k + 1;
  end loop;
  v_total := least(v_total, greatest(v_saldo, 0));   -- nunca deja el saldo en negativo
  if v_total > 0 then perform mover_saldo(p_liga, p_manager, -v_total, 'reparto_inicial'); end if;
  return k;
end $$;



-- ───────────── Logros de lo ya jugado (sin avisos) ─────────────
do $$
declare r record;
begin
  perform set_config('ff.sin_avisos', '1', true);
  for r in select id from miembros where estado = 'activo' loop
    perform evaluar_logros(r.id, null);
  end loop;
  perform set_config('ff.sin_avisos', '', true);
end $$;
