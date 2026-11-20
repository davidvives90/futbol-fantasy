-- 0037 · Avisos en el idioma de cada jugador (los textos se escriben en castellano y se traducen al crear el aviso).
alter table perfiles add column if not exists idioma text not null default 'es'
  check (idioma in ('es', 'ca', 'gl', 'eu', 'en', 'de', 'it', 'nl', 'fr'));

create table if not exists avisos_traducciones (
  orden     int  not null,
  patron    text not null,        -- expresión regular sobre el texto en castellano
  idioma    text not null,
  plantilla text not null,        -- \1, \2… = huecos del patrón
  primary key (orden, idioma)
);
create table if not exists logros_traducciones (
  es     text not null,
  idioma text not null,
  texto  text not null,
  primary key (es, idioma)
);
alter table avisos_traducciones enable row level security;
alter table logros_traducciones enable row level security;
revoke all on avisos_traducciones, logros_traducciones from anon, authenticated;

delete from avisos_traducciones where true;
insert into avisos_traducciones (orden, patron, idioma, plantilla)
select v.o, v.p, l.idioma, v.t[l.n]
  from (values
(1, '^Post-partido abierto ⚽$', array['Post-partit obert ⚽', 'Post-partido aberto ⚽', 'Partida ostekoa irekita ⚽', 'Post-match open ⚽', 'Nachbereitung offen ⚽', 'Post-partita aperto ⚽', 'Nabespreking open ⚽', 'Après-match ouvert ⚽']),
(2, '^Pon el resultado y tus notas \(1 minuto\) · hasta (.+)$', array['Posa el resultat i les teves notes (1 minut) · fins \1', 'Pon o resultado e as túas notas (1 minuto) · ata \1', 'Jarri emaitza eta zure notak (minutu 1) · \1 arte', 'Enter the result and your ratings (1 minute) · until \1', 'Ergebnis und Noten eintragen (1 Minute) · bis \1', 'Inserisci risultato e voti (1 minuto) · fino a \1', 'Vul uitslag en cijfers in (1 minuut) · tot \1', 'Saisis le résultat et tes notes (1 minute) · jusqu''au \1']),
(3, '^Pon el resultado y tus notas \(1 minuto\)$', array['Posa el resultat i les teves notes (1 minut)', 'Pon o resultado e as túas notas (1 minuto)', 'Jarri emaitza eta zure notak (minutu 1)', 'Enter the result and your ratings (1 minute)', 'Ergebnis und Noten eintragen (1 Minute)', 'Inserisci risultato e voti (1 minuto)', 'Vul uitslag en cijfers in (1 minuut)', 'Saisis le résultat et tes notes (1 minute)']),
(4, '^Hay datos en disputa$', array['Hi ha dades en disputa', 'Hai datos en disputa', 'Eztabaidan dauden datuak daude', 'Some data is disputed', 'Es gibt strittige Daten', 'Ci sono dati contestati', 'Er zijn betwiste gegevens', 'Des données sont contestées']),
(5, '^Revisa el acta del (.+) para cerrar la jornada$', array['Revisa l''acta del \1 per tancar la jornada', 'Revisa a acta do \1 para pechar a xornada', 'Berrikusi \1ko akta jardunaldia ixteko', 'Review the sheet for \1 to close the round', 'Prüfe das Protokoll vom \1, um den Spieltag abzuschließen', 'Rivedi il verbale del \1 per chiudere la giornata', 'Controleer het verslag van \1 om de speelronde af te sluiten', 'Vérifie la feuille du \1 pour clôturer la journée']),
(6, '^Puntos publicados 🏆$', array['Punts publicats 🏆', 'Puntos publicados 🏆', 'Puntuak argitaratuta 🏆', 'Points published 🏆', 'Punkte veröffentlicht 🏆', 'Punti pubblicati 🏆', 'Punten gepubliceerd 🏆', 'Points publiés 🏆']),
(7, '^Jornada del (.+) · MVP: (.+)$', array['Jornada del \1 · MVP: \2', 'Xornada do \1 · MVP: \2', '\1ko jardunaldia · MVP: \2', 'Round of \1 · MVP: \2', 'Spieltag vom \1 · MVP: \2', 'Giornata del \1 · MVP: \2', 'Speelronde van \1 · MVP: \2', 'Journée du \1 · MVP : \2']),
(8, '^Jornada del (.+)$', array['Jornada del \1', 'Xornada do \1', '\1ko jardunaldia', 'Round of \1', 'Spieltag vom \1', 'Giornata del \1', 'Speelronde van \1', 'Journée du \1']),
(9, '^Partido cancelado$', array['Partit cancel·lat', 'Partido cancelado', 'Partida ezeztatuta', 'Match cancelled', 'Spiel abgesagt', 'Partita annullata', 'Wedstrijd afgelast', 'Match annulé']),
(10, '^Se cancela el partido del (.+)$', array['Es cancel·la el partit del \1', 'Cancélase o partido do \1', '\1ko partida ezeztatu da', 'The match on \1 is cancelled', 'Das Spiel vom \1 fällt aus', 'La partita del \1 è annullata', 'De wedstrijd van \1 is afgelast', 'Le match du \1 est annulé']),
(11, '^Cambio de hora$', array['Canvi d''hora', 'Cambio de hora', 'Ordu-aldaketa', 'Time change', 'Uhrzeit geändert', 'Cambio di orario', 'Tijdswijziging', 'Changement d''heure']),
(12, '^El partido pasa a (.+)$', array['El partit passa a \1', 'O partido pasa a \1', 'Partida \1ra aldatu da', 'The match moves to \1', 'Das Spiel ist jetzt am \1', 'La partita si sposta a \1', 'De wedstrijd is verplaatst naar \1', 'Le match passe au \1']),
(13, '^¡Entras en la convocatoria! ✅$', array['Entres a la convocatòria! ✅', 'Entras na convocatoria! ✅', 'Deialdian sartu zara! ✅', 'You''re in the line-up! ✅', 'Du bist dabei! ✅', 'Sei convocato! ✅', 'Je staat in de opstelling! ✅', 'Tu es convoqué ! ✅']),
(14, '^Se ha liberado una plaza para el (.+)$', array['S''ha alliberat una plaça per al \1', 'Liberouse unha praza para o \1', '\1rako plaza bat libratu da', 'A spot opened up for \1', 'Ein Platz für \1 ist frei geworden', 'Si è liberato un posto per il \1', 'Er is een plek vrijgekomen voor \1', 'Une place s''est libérée pour le \1']),
(15, '^Te han quitado de la convocatoria$', array['T''han tret de la convocatòria', 'Quitáronte da convocatoria', 'Deialditik kendu zaituzte', 'You''ve been removed from the line-up', 'Du wurdest aus der Aufstellung genommen', 'Sei stato tolto dalla convocazione', 'Je bent uit de opstelling gehaald', 'Tu as été retiré de la convocation']),
(16, '^Te han apuntado \(lista de espera\)$', array['T''han apuntat (llista d''espera)', 'Apuntáronte (lista de espera)', 'Izena eman dizute (itxaron-zerrenda)', 'You''ve been signed up (waiting list)', 'Du wurdest eingetragen (Warteliste)', 'Ti hanno iscritto (lista d''attesa)', 'Je bent aangemeld (wachtlijst)', 'Tu as été inscrit (liste d''attente)']),
(17, '^Te han apuntado al partido$', array['T''han apuntat al partit', 'Apuntáronte ao partido', 'Partidan izena eman dizute', 'You''ve been signed up for the match', 'Du wurdest für das Spiel eingetragen', 'Ti hanno iscritto alla partita', 'Je bent aangemeld voor de wedstrijd', 'Tu as été inscrit au match']),
(18, '^Partido del (.+)$', array['Partit del \1', 'Partido do \1', '\1ko partida', 'Match on \1', 'Spiel am \1', 'Partita del \1', 'Wedstrijd van \1', 'Match du \1']),
(19, '^Oferta por (.+) 💰$', array['Oferta per \1 💰', 'Oferta por \1 💰', '\1rentzako eskaintza 💰', 'Offer for \1 💰', 'Angebot für \1 💰', 'Offerta per \1 💰', 'Bod op \1 💰', 'Offre pour \1 💰']),
(20, '^(.+) ofrece (.+) M$', array['\1 ofereix \2 M', '\1 ofrece \2 M', '\1(e)k \2 M eskaintzen ditu', '\1 offers \2 M', '\1 bietet \2 M', '\1 offre \2 M', '\1 biedt \2 M', '\1 propose \2 M']),
(21, '^Oferta aceptada ✅$', array['Oferta acceptada ✅', 'Oferta aceptada ✅', 'Eskaintza onartuta ✅', 'Offer accepted ✅', 'Angebot angenommen ✅', 'Offerta accettata ✅', 'Bod geaccepteerd ✅', 'Offre acceptée ✅']),
(22, '^Oferta rechazada$', array['Oferta rebutjada', 'Oferta rexeitada', 'Eskaintza baztertuta', 'Offer rejected', 'Angebot abgelehnt', 'Offerta rifiutata', 'Bod geweigerd', 'Offre refusée']),
(23, '^Te han pagado una cláusula$', array['T''han pagat una clàusula', 'Pagáronche unha cláusula', 'Klausula bat ordaindu dizute', 'Someone paid a release clause', 'Jemand hat eine Ausstiegsklausel gezahlt', 'Ti hanno pagato una clausola', 'Er is een afkoopsom betaald', 'On a payé une clause']),
(24, '^(.+) se va por (.+) M$', array['\1 se''n va per \2 M', '\1 vaise por \2 M', '\1 \2 M-tan doa', '\1 leaves for \2 M', '\1 geht für \2 M', '\1 va via per \2 M', '\1 vertrekt voor \2 M', '\1 part pour \2 M']),
(25, '^Convocatoria abierta ⚽$', array['Convocatòria oberta ⚽', 'Convocatoria aberta ⚽', 'Deialdia irekita ⚽', 'Line-up open ⚽', 'Aufstellung offen ⚽', 'Convocazione aperta ⚽', 'Opstelling open ⚽', 'Convocation ouverte ⚽']),
(26, '^¿Juegas el (.+)\? Pulsa «Voy» para apuntarte$', array['Jugues el \1? Prem «Hi vaig» per apuntar-t''hi', 'Xogas o \1? Preme «Vou» para apuntarte', '\1ean jokatzen duzu? Sakatu «Banoa» izena emateko', 'Playing on \1? Tap "I''m in" to sign up', 'Spielst du am \1? Tippe auf „Ich komme“', 'Giochi il \1? Tocca «Ci sono» per iscriverti', 'Speel je op \1? Tik op „Ik kom” om je aan te melden', 'Tu joues le \1 ? Appuie sur « J''y vais » pour t''inscrire']),
(27, '^Eres fijo: tienes plaza hasta (.+)\. Pulsa «Voy» o «No voy»$', array['Ets fix: tens plaça fins \1. Prem «Hi vaig» o «No hi vaig»', 'Es fixo: tes praza ata \1. Preme «Vou» ou «Non vou»', 'Finkoa zara: \1 arte duzu plaza. Sakatu «Banoa» edo «Ez noa»', 'You''re a regular: your spot is held until \1. Tap "I''m in" or "I''m out"', 'Du bist Stammspieler: dein Platz ist bis \1 reserviert. Tippe „Ich komme“ oder „Ich komme nicht“', 'Sei fisso: il posto è tuo fino a \1. Tocca «Ci sono» o «Non ci sono»', 'Je bent vaste speler: je plek is gereserveerd tot \1. Tik „Ik kom” of „Ik kom niet”', 'Tu es titulaire : ta place est réservée jusqu''au \1. Appuie sur « J''y vais » ou « Je n''y vais pas »']),
(28, '^Falta 1 jugador$', array['Falta 1 jugador', 'Falta 1 xogador', 'Jokalari 1 falta da', '1 player short', '1 Spieler fehlt', 'Manca 1 giocatore', 'Er ontbreekt 1 speler', 'Il manque 1 joueur']),
(29, '^Faltan ([0-9]+) jugadores$', array['Falten \1 jugadors', 'Faltan \1 xogadores', '\1 jokalari falta dira', '\1 players short', '\1 Spieler fehlen', 'Mancano \1 giocatori', 'Er ontbreken \1 spelers', 'Il manque \1 joueurs']),
(30, '^¿Juegas el (.+)\?$', array['Jugues el \1?', 'Xogas o \1?', '\1ean jokatzen duzu?', 'Playing on \1?', 'Spielst du am \1?', 'Giochi il \1?', 'Speel je op \1?', 'Tu joues le \1 ?']),
(31, '^Revisa tu alineación$', array['Revisa la teva alineació', 'Revisa a túa aliñación', 'Berrikusi zure hamaikakoa', 'Check your line-up', 'Prüfe deine Aufstellung', 'Controlla la tua formazione', 'Controleer je opstelling', 'Vérifie ta composition']),
(32, '^Se cierra en menos de 1 h \(partido del (.+)\)$', array['Es tanca en menys d''1 h (partit del \1)', 'Péchase en menos de 1 h (partido do \1)', 'Ordubete baino lehen ixten da (\1ko partida)', 'Closes in under 1 h (match on \1)', 'Schließt in weniger als 1 Std. (Spiel am \1)', 'Si chiude tra meno di 1 h (partita del \1)', 'Sluit binnen 1 uur (wedstrijd van \1)', 'Se ferme dans moins d''1 h (match du \1)']),
(33, '^Último aviso: post-partido$', array['Últim avís: post-partit', 'Último aviso: post-partido', 'Azken abisua: partida ostekoa', 'Last call: post-match', 'Letzte Erinnerung: Nachbereitung', 'Ultimo avviso: post-partita', 'Laatste herinnering: nabespreking', 'Dernier rappel : après-match']),
(34, '^La votación cierra a las (.+) \(1 minuto\)$', array['La votació tanca a les \1 (1 minut)', 'A votación pecha ás \1 (1 minuto)', 'Bozketa \1etan ixten da (minutu 1)', 'Voting closes at \1 (1 minute)', 'Die Abstimmung endet um \1 (1 Minute)', 'La votazione chiude alle \1 (1 minuto)', 'De stemming sluit om \1 (1 minuut)', 'Le vote se termine à \1 (1 minute)']),
(35, '^Se acabó tu baja 💪$', array['S''ha acabat la teva baixa 💪', 'Rematou a túa baixa 💪', 'Zure baja amaitu da 💪', 'Your absence is over 💪', 'Deine Abwesenheit ist vorbei 💪', 'La tua assenza è finita 💪', 'Je afwezigheid is voorbij 💪', 'Ton absence est terminée 💪']),
(36, '^¿Vuelves\? Apúntate al próximo partido$', array['Tornes? Apunta''t al proper partit', 'Volves? Apúntate ao próximo partido', 'Itzultzen zara? Eman izena hurrengo partidan', 'Coming back? Sign up for the next match', 'Bist du zurück? Melde dich fürs nächste Spiel an', 'Torni? Iscriviti alla prossima partita', 'Ben je terug? Meld je aan voor de volgende wedstrijd', 'Tu reviens ? Inscris-toi au prochain match']),
(37, '^Tienes un pago pendiente 💸$', array['Tens un pagament pendent 💸', 'Tes un pagamento pendente 💸', 'Ordainketa bat duzu zain 💸', 'You have a pending payment 💸', 'Du hast eine offene Zahlung 💸', 'Hai un pagamento in sospeso 💸', 'Je hebt een openstaande betaling 💸', 'Tu as un paiement en attente 💸']),
(38, '^Debes (.+) en «(.+)»\. Cuando pagues, pulsa «Ya he pagado» en Caja$', array['Deus \1 a «\2». Quan paguis, prem «Ja he pagat» a Caixa', 'Debes \1 en «\2». Cando pagues, preme «Xa paguei» en Caixa', '\1 zor duzu «\2» ligan. Ordaintzean, sakatu «Ordaindu dut» Kutxan', 'You owe \1 in "\2". Once paid, tap "I''ve paid" in Cash', 'Du schuldest \1 in „\2“. Tippe nach der Zahlung in der Kasse auf „Ich habe bezahlt“', 'Devi \1 in «\2». Dopo aver pagato, tocca «Ho pagato» in Cassa', 'Je bent \1 schuldig in „\2”. Tik na betalen op „Ik heb betaald” in Kas', 'Tu dois \1 dans « \2 ». Après paiement, appuie sur « J''ai payé » dans Caisse']),
(39, '^Pago por confirmar 💸$', array['Pagament per confirmar 💸', 'Pagamento por confirmar 💸', 'Berresteko ordainketa 💸', 'Payment to confirm 💸', 'Zahlung zu bestätigen 💸', 'Pagamento da confermare 💸', 'Te bevestigen betaling 💸', 'Paiement à confirmer 💸']),
(40, '^(.+) dice que ha pagado (.+) \((.+)\)$', array['\1 diu que ha pagat \2 (\3)', '\1 di que pagou \2 (\3)', '\1(e)k \2 ordaindu dituela dio (\3)', '\1 says they paid \2 (\3)', '\1 sagt, er hat \2 bezahlt (\3)', '\1 dice di aver pagato \2 (\3)', '\1 zegt \2 te hebben betaald (\3)', '\1 dit avoir payé \2 (\3)']),
(41, '^Pago confirmado ✅$', array['Pagament confirmat ✅', 'Pagamento confirmado ✅', 'Ordainketa berretsita ✅', 'Payment confirmed ✅', 'Zahlung bestätigt ✅', 'Pagamento confermato ✅', 'Betaling bevestigd ✅', 'Paiement confirmé ✅']),
(42, '^Pago no confirmado$', array['Pagament no confirmat', 'Pagamento non confirmado', 'Ordainketa berretsi gabe', 'Payment not confirmed', 'Zahlung nicht bestätigt', 'Pagamento non confermato', 'Betaling niet bevestigd', 'Paiement non confirmé']),
(43, '^El administrador ha apuntado tu pago de (.+)$', array['L''administrador ha apuntat el teu pagament de \1', 'O administrador anotou o teu pagamento de \1', 'Administratzaileak zure \1ko ordainketa idatzi du', 'The admin has recorded your payment of \1', 'Der Admin hat deine Zahlung von \1 verbucht', 'L''amministratore ha registrato il tuo pagamento di \1', 'De beheerder heeft je betaling van \1 geboekt', 'L''administrateur a enregistré ton paiement de \1']),
(44, '^El administrador no ha encontrado tu pago de (.+)\. Habla con él\.$', array['L''administrador no ha trobat el teu pagament de \1. Parla-hi.', 'O administrador non atopou o teu pagamento de \1. Fala con el.', 'Administratzaileak ez du zure \1ko ordainketa aurkitu. Hitz egin berarekin.', 'The admin couldn''t find your payment of \1. Have a word with them.', 'Der Admin hat deine Zahlung von \1 nicht gefunden. Sprich mit ihm.', 'L''amministratore non ha trovato il tuo pagamento di \1. Parlagli.', 'De beheerder vond je betaling van \1 niet. Neem contact op.', 'L''administrateur n''a pas trouvé ton paiement de \1. Parle-lui.']),
(45, '^Nueva votación 🗳️$', array['Nova votació 🗳️', 'Nova votación 🗳️', 'Bozketa berria 🗳️', 'New poll 🗳️', 'Neue Abstimmung 🗳️', 'Nuova votazione 🗳️', 'Nieuwe stemming 🗳️', 'Nouveau vote 🗳️']),
(46, '^Votación cerrada$', array['Votació tancada', 'Votación pechada', 'Bozketa itxita', 'Poll closed', 'Abstimmung beendet', 'Votazione chiusa', 'Stemming gesloten', 'Vote clos']),
(47, '^(.+): ganó «(.+)»$', array['\1: ha guanyat «\2»', '\1: gañou «\2»', '\1: «\2» irabazi du', '\1: "\2" won', '\1: „\2“ hat gewonnen', '\1: ha vinto «\2»', '\1: „\2” heeft gewonnen', '\1 : « \2 » l''emporte']),
(48, '^(.+): empate, sin ganadora$', array['\1: empat, sense guanyadora', '\1: empate, sen gañadora', '\1: berdinketa, irabazlerik gabe', '\1: tie, no winner', '\1: Gleichstand, kein Sieger', '\1: pareggio, nessuna vincitrice', '\1: gelijkspel, geen winnaar', '\1 : égalité, pas de gagnant']),
(49, '^(.+) cerrada 🏆$', array['\1 tancada 🏆', '\1 pechada 🏆', '\1 itxita 🏆', '\1 closed 🏆', '\1 abgeschlossen 🏆', '\1 chiusa 🏆', '\1 afgesloten 🏆', '\1 clôturée 🏆']),
(50, '^Mira quién se ha llevado los premios$', array['Mira qui s''ha endut els premis', 'Mira quen levou os premios', 'Ikusi nork eraman dituen sariak', 'See who won the awards', 'Sieh, wer die Preise gewonnen hat', 'Guarda chi ha vinto i premi', 'Kijk wie de prijzen heeft gewonnen', 'Découvre qui a remporté les prix'])
) v(o, p, t)
  cross join unnest(array['ca','gl','eu','en','de','it','nl','fr']) with ordinality l(idioma, n);

delete from logros_traducciones where true;
insert into logros_traducciones (es, idioma, texto)
select v.e, l.idioma, v.t[l.n]
  from (values
('Primer gol', array['Primer gol', 'Primeiro gol', 'Lehen gola', 'First goal', 'Erstes Tor', 'Primo gol', 'Eerste doelpunt', 'Premier but']),
('Hat-trick', array['Hat-trick', 'Hat-trick', 'Hat-tricka', 'Hat-trick', 'Hattrick', 'Tripletta', 'Hattrick', 'Triplé']),
('Manita (5 goles)', array['Manita (5 gols)', 'Manita (5 goles)', 'Bost gol', 'Five goals', 'Fünferpack', 'Cinquina (5 gol)', 'Vijf goals', 'Quintuplé (5 buts)']),
('10 goles', array['10 gols', '10 goles', '10 gol', '10 goals', '10 Tore', '10 gol', '10 doelpunten', '10 buts']),
('25 goles', array['25 gols', '25 goles', '25 gol', '25 goals', '25 Tore', '25 gol', '25 doelpunten', '25 buts']),
('50 goles', array['50 gols', '50 goles', '50 gol', '50 goals', '50 Tore', '50 gol', '50 doelpunten', '50 buts']),
('100 goles', array['100 gols', '100 goles', '100 gol', '100 goals', '100 Tore', '100 gol', '100 doelpunten', '100 buts']),
('Primer MVP', array['Primer MVP', 'Primeiro MVP', 'Lehen MVPa', 'First MVP', 'Erster MVP', 'Primo MVP', 'Eerste MVP', 'Premier MVP']),
('5 MVPs', array['5 MVP', '5 MVP', '5 MVP', '5 MVPs', '5 MVPs', '5 MVP', '5 MVP''s', '5 MVP']),
('10 MVPs', array['10 MVP', '10 MVP', '10 MVP', '10 MVPs', '10 MVPs', '10 MVP', '10 MVP''s', '10 MVP']),
('10 partidos', array['10 partits', '10 partidos', '10 partida', '10 matches', '10 Spiele', '10 partite', '10 wedstrijden', '10 matchs']),
('25 partidos', array['25 partits', '25 partidos', '25 partida', '25 matches', '25 Spiele', '25 partite', '25 wedstrijden', '25 matchs']),
('50 partidos', array['50 partits', '50 partidos', '50 partida', '50 matches', '50 Spiele', '50 partite', '50 wedstrijden', '50 matchs']),
('100 partidos', array['100 partits', '100 partidos', '100 partida', '100 matches', '100 Spiele', '100 partite', '100 wedstrijden', '100 matchs']),
('10 partidos seguidos sin faltar', array['10 partits seguits sense faltar', '10 partidos seguidos sen faltar', '10 partida jarraian huts egin gabe', '10 matches in a row', '10 Spiele in Folge', '10 partite di fila senza mancare', '10 wedstrijden op rij', '10 matchs d''affilée']),
('5 partidos sin perder', array['5 partits sense perdre', '5 partidos sen perder', '5 partida galdu gabe', '5 matches unbeaten', '5 Spiele ungeschlagen', '5 partite senza perdere', '5 wedstrijden ongeslagen', '5 matchs sans défaite']),
('5 porterías a cero', array['5 porteries a zero', '5 porterías a cero', '5 atea hutsean', '5 clean sheets', '5 Spiele ohne Gegentor', '5 porte inviolate', '5 keer de nul', '5 clean sheets'])
) v(e, t)
  cross join unnest(array['ca','gl','eu','en','de','it','nl','fr']) with ordinality l(idioma, n);

create or replace function _logro_en(p_es text, p_idioma text) returns text
language sql stable security definer set search_path = public as $$
  select coalesce((select texto from logros_traducciones where es = p_es and idioma = p_idioma), p_es) $$;

-- Traduce un aviso escrito en castellano al idioma del destinatario (si no hay plantilla, se queda igual)
create or replace function traducir_aviso(p_texto text, p_idioma text) returns text
language plpgsql stable security definer set search_path = public as $$
declare r record; v text := p_texto; v_dias text[]; m text[];
begin
  if p_texto is null or p_idioma is null or p_idioma = 'es' or p_texto = '' then return p_texto; end if;
  -- logros: el nombre del logro va dentro del texto
  if p_texto ~ '^🏅 ' then
    return '🏅 ' || _logro_en(substr(p_texto, 3), p_idioma);
  end if;
  m := regexp_match(p_texto, '^¡Nuevo logro: (.+)!$');
  if m is not null then
    return replace(case p_idioma when 'ca' then 'Nou assoliment: #1!' when 'gl' then 'Novo logro: #1!' when 'eu' then 'Lorpen berria: #1!' when 'en' then 'New achievement: #1!' when 'de' then 'Neuer Erfolg: #1!' when 'it' then 'Nuovo traguardo: #1!' when 'nl' then 'Nieuwe prestatie: #1!' when 'fr' then 'Nouveau succès : #1 !' end,
                   '#1', _logro_en(m[1], p_idioma));
  end if;
  m := regexp_match(p_texto, '^(.+) consigue «(.+)»$');
  if m is not null then
    return replace(replace(case p_idioma when 'ca' then '#1 aconsegueix «#2»' when 'gl' then '#1 consegue «#2»' when 'eu' then '#1(e)k «#2» lortu du' when 'en' then '#1 earns "#2"' when 'de' then '#1 erreicht „#2“' when 'it' then '#1 ottiene «#2»' when 'nl' then '#1 behaalt „#2”' when 'fr' then '#1 obtient « #2 »' end,
                   '#1', m[1]), '#2', _logro_en(m[2], p_idioma));
  end if;
  for r in select patron, plantilla from avisos_traducciones where idioma = p_idioma order by orden loop
    if p_texto ~ r.patron then
      v := regexp_replace(p_texto, r.patron, r.plantilla);
      exit;
    end if;
  end loop;
  -- días de la semana de fecha_corta («lun 24/11 21:00»)
  v_dias := case p_idioma when 'ca' then array['dl', 'dt', 'dc', 'dj', 'dv', 'ds', 'dg'] when 'gl' then array['lun', 'mar', 'mér', 'xov', 'ven', 'sáb', 'dom'] when 'eu' then array['al', 'ar', 'az', 'og', 'or', 'lr', 'ig'] when 'en' then array['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'] when 'de' then array['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'] when 'it' then array['lun', 'mar', 'mer', 'gio', 'ven', 'sab', 'dom'] when 'nl' then array['ma', 'di', 'wo', 'do', 'vr', 'za', 'zo'] when 'fr' then array['lun', 'mar', 'mer', 'jeu', 'ven', 'sam', 'dim'] end;
  if v_dias is not null then
    v := regexp_replace(v, '(^|[^[:alpha:]])lun ([0-9]{2}/)', '\1' || v_dias[1] || ' \2', 'g');
    v := regexp_replace(v, '(^|[^[:alpha:]])mar ([0-9]{2}/)', '\1' || v_dias[2] || ' \2', 'g');
    v := regexp_replace(v, '(^|[^[:alpha:]])mié ([0-9]{2}/)', '\1' || v_dias[3] || ' \2', 'g');
    v := regexp_replace(v, '(^|[^[:alpha:]])jue ([0-9]{2}/)', '\1' || v_dias[4] || ' \2', 'g');
    v := regexp_replace(v, '(^|[^[:alpha:]])vie ([0-9]{2}/)', '\1' || v_dias[5] || ' \2', 'g');
    v := regexp_replace(v, '(^|[^[:alpha:]])sáb ([0-9]{2}/)', '\1' || v_dias[6] || ' \2', 'g');
    v := regexp_replace(v, '(^|[^[:alpha:]])dom ([0-9]{2}/)', '\1' || v_dias[7] || ' \2', 'g');
  end if;
  return v;
end $$;

-- Crea una notificación por perfil (sin duplicados, ignora nulos), ya traducida a su idioma.
create or replace function notificar(p_perfiles uuid[], p_liga uuid, p_tipo text, p_titulo text, p_cuerpo text,
                                     p_ruta text default null) returns int
language plpgsql security definer set search_path = public as $$
declare k int;
begin
  insert into notificaciones (perfil_id, liga_id, tipo, titulo, cuerpo, ruta)
  select u, p_liga, p_tipo, traducir_aviso(p_titulo, coalesce(pf.idioma, 'es')),
         traducir_aviso(coalesce(p_cuerpo, ''), coalesce(pf.idioma, 'es')), p_ruta
    from (select distinct u from unnest(p_perfiles) u where u is not null) d
    left join perfiles pf on pf.id = d.u;
  get diagnostics k = row_count;
  return k;
end $$;

revoke execute on function traducir_aviso(text, text), _logro_en(text, text) from public, anon, authenticated;
