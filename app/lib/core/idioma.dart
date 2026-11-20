import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'liga_activa.dart';

/// Idiomas de la app: los oficiales de España, inglés, alemán, italiano, holandés y francés.
const idiomas = <String, String>{
  'es': 'Castellano',
  'ca': 'Català',
  'gl': 'Galego',
  'eu': 'Euskara',
  'en': 'English',
  'de': 'Deutsch',
  'it': 'Italiano',
  'nl': 'Nederlands',
  'fr': 'Français',
};

/// Idioma en uso (lo fija IdiomaNotifier). Lo usan tr() y los formatos de fecha.
String idiomaActual = 'es';

const _orden = ['ca', 'gl', 'eu', 'en', 'de', 'it', 'nl', 'fr'];

/// Traduce un texto escrito en castellano. Si aún no tiene traducción, se queda en castellano.
String tr(String es) {
  if (idiomaActual == 'es') return es;
  final i = _orden.indexOf(idiomaActual);
  final t = _textos[es];
  return (i < 0 || t == null) ? es : t[i];
}

/// Text traducido. Se puede usar como `const Tx('Guardar')` y se redibuja al cambiar de idioma.
class Tx extends StatelessWidget {
  const Tx(this.texto, {super.key, this.style, this.textAlign, this.overflow, this.maxLines, this.softWrap});
  final String texto;
  final TextStyle? style;
  final TextAlign? textAlign;
  final TextOverflow? overflow;
  final int? maxLines;
  final bool? softWrap;

  @override
  Widget build(BuildContext context) {
    Localizations.maybeLocaleOf(context); // dependencia: se reconstruye al cambiar el idioma
    return Text(tr(texto), style: style, textAlign: textAlign, overflow: overflow, maxLines: maxLines, softWrap: softWrap);
  }
}

const _clave = 'idioma_app';

class IdiomaNotifier extends Notifier<String> {
  @override
  String build() {
    var c = ref.watch(prefsProvider).getString(_clave);
    if (c == null || !idiomas.containsKey(c)) {
      final sistema = WidgetsBinding.instance.platformDispatcher.locale.languageCode;
      c = idiomas.containsKey(sistema) ? sistema : 'es';
    }
    idiomaActual = c;
    return c;
  }

  Future<void> elegir(String codigo) async {
    idiomaActual = codigo;
    state = codigo;
    await ref.read(prefsProvider).setString(_clave, codigo);
  }
}

final idiomaProvider = NotifierProvider<IdiomaNotifier, String>(IdiomaNotifier.new);

/// Traducciones (orden: català, galego, euskara, English, Deutsch, italiano, Nederlands, français).
const _textos = <String, List<String>>{
  'Partidos': ['Partits', 'Partidos', 'Partidak', 'Matches', 'Spiele', 'Partite', 'Wedstrijden', 'Matchs'],
  'Fantasy': ['Fantasy', 'Fantasy', 'Fantasy', 'Fantasy', 'Fantasy', 'Fantasy', 'Fantasy', 'Fantasy'],
  'Clasificación': ['Classificació', 'Clasificación', 'Sailkapena', 'Standings', 'Tabelle', 'Classifica', 'Stand', 'Classement'],
  'Caja': ['Caixa', 'Caixa', 'Kutxa', 'Cash', 'Kasse', 'Cassa', 'Kas', 'Caisse'],
  'Liga': ['Lliga', 'Liga', 'Liga', 'League', 'Liga', 'Lega', 'Competitie', 'Ligue'],
  'Mi perfil': ['El meu perfil', 'O meu perfil', 'Nire profila', 'My profile', 'Mein Profil', 'Il mio profilo', 'Mijn profiel', 'Mon profil'],
  'Cambiar de liga': ['Canviar de lliga', 'Cambiar de liga', 'Liga aldatu', 'Switch league', 'Liga wechseln', 'Cambia lega', 'Wissel van competitie', 'Changer de ligue'],
  'Avisos': ['Avisos', 'Avisos', 'Abisuak', 'Notifications', 'Benachrichtigungen', 'Notifiche', 'Meldingen', 'Notifications'],
  'Voy': ['Hi vaig', 'Vou', 'Banoa', 'I\'m in', 'Ich komme', 'Ci sono', 'Ik kom', 'J\'y vais'],
  'No voy': ['No hi vaig', 'Non vou', 'Ez noa', 'I\'m out', 'Ich komme nicht', 'Non ci sono', 'Ik kom niet', 'Je n\'y vais pas'],
  'Duda': ['Dubte', 'Dúbida', 'Zalantza', 'Maybe', 'Vielleicht', 'Forse', 'Misschien', 'Peut-être'],
  'Lista de espera': ['Llista d\'espera', 'Lista de espera', 'Itxaron-zerrenda', 'Waiting list', 'Warteliste', 'Lista d\'attesa', 'Wachtlijst', 'Liste d\'attente'],
  'Nuevo partido': ['Nou partit', 'Novo partido', 'Partida berria', 'New match', 'Neues Spiel', 'Nuova partita', 'Nieuwe wedstrijd', 'Nouveau match'],
  'Equipos': ['Equips', 'Equipos', 'Taldeak', 'Teams', 'Teams', 'Squadre', 'Teams', 'Équipes'],
  'Hora pendiente de confirmar': ['Hora pendent de confirmar', 'Hora pendente de confirmar', 'Ordua berresteko', 'Time to be confirmed', 'Uhrzeit noch offen', 'Orario da confermare', 'Tijd nog te bevestigen', 'Heure à confirmer'],
  'Hora confirmada': ['Hora confirmada', 'Hora confirmada', 'Ordua berretsita', 'Time confirmed', 'Uhrzeit bestätigt', 'Orario confermato', 'Tijd bevestigd', 'Heure confirmée'],
  'Hora por confirmar': ['Hora per confirmar', 'Hora por confirmar', 'Ordua berresteko', 'Time TBC', 'Uhrzeit offen', 'Orario da confermare', 'Tijd nog onbekend', 'Heure à confirmer'],
  'De baja': ['De baixa', 'De baixa', 'Baja hartuta', 'Unavailable', 'Abwesend', 'Assente', 'Afwezig', 'Absent'],
  'confirmados': ['confirmats', 'confirmados', 'berretsiak', 'confirmed', 'bestätigt', 'confermati', 'bevestigd', 'confirmés'],
  'por jugador': ['per jugador', 'por xogador', 'jokalariko', 'per player', 'pro Spieler', 'a giocatore', 'per speler', 'par joueur'],
  'Entrarás automáticamente si alguien se da de baja.': ['Entraràs automàticament si algú es dona de baixa.', 'Entrarás automaticamente se alguén se dá de baixa.', 'Automatikoki sartuko zara norbaitek baja ematen badu.', 'You\'ll get in automatically if someone drops out.', 'Du rückst automatisch nach, wenn jemand absagt.', 'Entrerai automaticamente se qualcuno si ritira.', 'Je komt automatisch erbij als iemand afzegt.', 'Tu entreras automatiquement si quelqu\'un se désiste.'],
  'MVP': ['MVP', 'MVP', 'MVP', 'MVP', 'MVP', 'MVP', 'MVP', 'MVP'],
  'No me fijé': ['No m\'hi vaig fixar', 'Non me fixei', 'Ez nintzen ohartu', 'Didn\'t notice', 'Nicht gesehen', 'Non ho visto', 'Niet gezien', 'Pas vu'],
  '¿No te fijaste?': ['No t\'hi vas fixar?', 'Non te fixaches?', 'Ez zinen ohartu?', 'Didn\'t notice?', 'Nicht gesehen?', 'Non hai visto?', 'Niet gezien?', 'Pas vu ?'],
  '¿Cómo se elige el MVP?': ['Com es tria l\'MVP?', 'Como se elixe o MVP?', 'Nola aukeratzen da MVPa?', 'How is the MVP chosen?', 'Wie wird der MVP gewählt?', 'Come si sceglie l\'MVP?', 'Hoe wordt de MVP gekozen?', 'Comment est choisi le MVP ?'],
  'Toca para sumar · mantén pulsado para restar': ['Toca per sumar · mantén premut per restar', 'Toca para sumar · mantén premido para restar', 'Ukitu gehitzeko · eutsi kentzeko', 'Tap to add · long-press to subtract', 'Tippen zum Erhöhen · lange drücken zum Verringern', 'Tocca per aggiungere · tieni premuto per togliere', 'Tik om op te tellen · lang drukken om af te trekken', 'Touchez pour ajouter · appui long pour retirer'],
  'Menos de 1 minuto · anónimo · se cruza con el resto': ['Menys d\'1 minut · anònim · es creua amb la resta', 'Menos de 1 minuto · anónimo · crúzase co resto', 'Minutu bat baino gutxiago · anonimoa · besteekin gurutzatzen da', 'Less than 1 minute · anonymous · cross-checked with the rest', 'Unter 1 Minute · anonym · wird mit den anderen abgeglichen', 'Meno di 1 minuto · anonimo · confrontato con gli altri', 'Minder dan 1 minuut · anoniem · vergeleken met de rest', 'Moins d\'1 minute · anonyme · recoupé avec les autres'],
  '¡Listo! Ya has enviado el resultado y tus notas.': ['Fet! Ja has enviat el resultat i les teves notes.', 'Listo! Xa enviaches o resultado e as túas notas.', 'Eginda! Emaitza eta zure notak bidali dituzu.', 'Done! You\'ve sent the result and your ratings.', 'Fertig! Ergebnis und Noten sind gesendet.', 'Fatto! Hai inviato risultato e voti.', 'Klaar! Je hebt de uitslag en je cijfers verstuurd.', 'C\'est fait ! Résultat et notes envoyés.'],
  'Corregir': ['Corregir', 'Corrixir', 'Zuzendu', 'Edit', 'Korrigieren', 'Correggi', 'Corrigeren', 'Corriger'],
  'Resultado consolidado': ['Resultat consolidat', 'Resultado consolidado', 'Behin betiko emaitza', 'Final result', 'Endergebnis', 'Risultato definitivo', 'Definitieve uitslag', 'Résultat final'],
  'Cancelar': ['Cancel·lar', 'Cancelar', 'Utzi', 'Cancel', 'Abbrechen', 'Annulla', 'Annuleren', 'Annuler'],
  'Guardar': ['Desar', 'Gardar', 'Gorde', 'Save', 'Speichern', 'Salva', 'Opslaan', 'Enregistrer'],
  'Aceptar': ['Acceptar', 'Aceptar', 'Onartu', 'OK', 'OK', 'OK', 'OK', 'OK'],
  'Cerrar': ['Tancar', 'Pechar', 'Itxi', 'Close', 'Schließen', 'Chiudi', 'Sluiten', 'Fermer'],
  'Eliminar': ['Eliminar', 'Eliminar', 'Ezabatu', 'Delete', 'Löschen', 'Elimina', 'Verwijderen', 'Supprimer'],
  'Añadir': ['Afegir', 'Engadir', 'Gehitu', 'Add', 'Hinzufügen', 'Aggiungi', 'Toevoegen', 'Ajouter'],
  'Atrás': ['Enrere', 'Atrás', 'Atzera', 'Back', 'Zurück', 'Indietro', 'Terug', 'Retour'],
  'Saltar': ['Ometre', 'Saltar', 'Saltatu', 'Skip', 'Überspringen', 'Salta', 'Overslaan', 'Passer'],
  'Reintentar': ['Tornar-ho a provar', 'Tentar de novo', 'Saiatu berriro', 'Try again', 'Erneut versuchen', 'Riprova', 'Opnieuw proberen', 'Réessayer'],
  'Entendido': ['Entesos', 'Entendido', 'Ulertuta', 'Got it', 'Verstanden', 'Capito', 'Begrepen', 'Compris'],
  'Sí': ['Sí', 'Si', 'Bai', 'Yes', 'Ja', 'Sì', 'Ja', 'Oui'],
  'No': ['No', 'Non', 'Ez', 'No', 'Nein', 'No', 'Nee', 'Non'],
  'Crear': ['Crear', 'Crear', 'Sortu', 'Create', 'Erstellen', 'Crea', 'Aanmaken', 'Créer'],
  'Registrar': ['Registrar', 'Rexistrar', 'Erregistratu', 'Record', 'Erfassen', 'Registra', 'Registreren', 'Enregistrer'],
  'Rechazar': ['Rebutjar', 'Rexeitar', 'Baztertu', 'Reject', 'Ablehnen', 'Rifiuta', 'Weigeren', 'Refuser'],
  'Avisar': ['Avisar', 'Avisar', 'Abisatu', 'Notify', 'Benachrichtigen', 'Avvisa', 'Melden', 'Prévenir'],
  'Opciones': ['Opcions', 'Opcións', 'Aukerak', 'Options', 'Optionen', 'Opzioni', 'Opties', 'Options'],
  'Tú': ['Tu', 'Ti', 'Zu', 'You', 'Du', 'Tu', 'Jij', 'Toi'],
  'Empate': ['Empat', 'Empate', 'Berdinketa', 'Draw', 'Unentschieden', 'Pareggio', 'Gelijkspel', 'Match nul'],
  'Apariencia': ['Aparença', 'Aparencia', 'Itxura', 'Appearance', 'Darstellung', 'Aspetto', 'Weergave', 'Apparence'],
  'Claro': ['Clar', 'Claro', 'Argia', 'Light', 'Hell', 'Chiaro', 'Licht', 'Clair'],
  'Oscuro': ['Fosc', 'Escuro', 'Iluna', 'Dark', 'Dunkel', 'Scuro', 'Donker', 'Sombre'],
  'Sistema': ['Sistema', 'Sistema', 'Sistema', 'System', 'System', 'Sistema', 'Systeem', 'Système'],
  'Cerrar sesión': ['Tancar la sessió', 'Pechar sesión', 'Saioa itxi', 'Sign out', 'Abmelden', 'Esci', 'Uitloggen', 'Se déconnecter'],
  'Eliminar mi cuenta': ['Eliminar el meu compte', 'Eliminar a miña conta', 'Nire kontua ezabatu', 'Delete my account', 'Mein Konto löschen', 'Elimina il mio account', 'Mijn account verwijderen', 'Supprimer mon compte'],
  'Política de privacidad': ['Política de privacitat', 'Política de privacidade', 'Pribatutasun-politika', 'Privacy policy', 'Datenschutzerklärung', 'Informativa sulla privacy', 'Privacybeleid', 'Politique de confidentialité'],
  'Privacidad y anuncios': ['Privacitat i anuncis', 'Privacidade e anuncios', 'Pribatutasuna eta iragarkiak', 'Privacy and ads', 'Datenschutz und Werbung', 'Privacy e annunci', 'Privacy en advertenties', 'Confidentialité et publicités'],
  'Guía y normas': ['Guia i normes', 'Guía e normas', 'Gida eta arauak', 'Guide and rules', 'Anleitung und Regeln', 'Guida e regole', 'Gids en regels', 'Guide et règles'],
  'Guía y normas de la liga': ['Guia i normes de la lliga', 'Guía e normas da liga', 'Ligaren gida eta arauak', 'League guide and rules', 'Anleitung und Regeln der Liga', 'Guida e regole della lega', 'Gids en regels van de competitie', 'Guide et règles de la ligue'],
  'Panel máster': ['Tauler màster', 'Panel máster', 'Master panela', 'Master panel', 'Master-Bereich', 'Pannello master', 'Masterpaneel', 'Panneau master'],
  'Mis ligas': ['Les meves lligues', 'As miñas ligas', 'Nire ligak', 'My leagues', 'Meine Ligen', 'Le mie leghe', 'Mijn competities', 'Mes ligues'],
  'Crear liga': ['Crear lliga', 'Crear liga', 'Liga sortu', 'Create league', 'Liga erstellen', 'Crea lega', 'Competitie aanmaken', 'Créer une ligue'],
  'Unirse con código': ['Unir-se amb codi', 'Unirse con código', 'Kodearekin batu', 'Join with code', 'Mit Code beitreten', 'Unisciti con codice', 'Deelnemen met code', 'Rejoindre avec un code'],
  'Unirse a una liga': ['Unir-se a una lliga', 'Unirse a unha liga', 'Liga batera batu', 'Join a league', 'Einer Liga beitreten', 'Unisciti a una lega', 'Deelnemen aan een competitie', 'Rejoindre une ligue'],
  'Buscar ligas': ['Cercar lligues', 'Buscar ligas', 'Ligak bilatu', 'Find leagues', 'Ligen suchen', 'Cerca leghe', 'Competities zoeken', 'Chercher des ligues'],
  'Abandonar la liga': ['Abandonar la lliga', 'Abandonar a liga', 'Liga utzi', 'Leave league', 'Liga verlassen', 'Lascia la lega', 'Competitie verlaten', 'Quitter la ligue'],
  'Fútbol Fantasy': ['Fútbol Fantasy', 'Fútbol Fantasy', 'Fútbol Fantasy', 'Fútbol Fantasy', 'Fútbol Fantasy', 'Fútbol Fantasy', 'Fútbol Fantasy', 'Fútbol Fantasy'],
  'Convocatorias, caja y liga Fantasy con tus amigos': ['Convocatòries, caixa i lliga Fantasy amb els teus amics', 'Convocatorias, caixa e liga Fantasy cos teus amigos', 'Deialdiak, kutxa eta Fantasy liga zure lagunekin', 'Line-ups, money and a Fantasy league with your friends', 'Aufstellungen, Kasse und Fantasy-Liga mit deinen Freunden', 'Convocazioni, cassa e lega Fantasy con i tuoi amici', 'Opstellingen, kas en Fantasy-competitie met je vrienden', 'Convocations, caisse et ligue Fantasy entre amis'],
  'Continuar con Google': ['Continuar amb Google', 'Continuar con Google', 'Jarraitu Googlerekin', 'Continue with Google', 'Weiter mit Google', 'Continua con Google', 'Doorgaan met Google', 'Continuer avec Google'],
  'Usar otro email': ['Fer servir un altre correu', 'Usar outro correo', 'Beste posta bat erabili', 'Use another email', 'Andere E-Mail verwenden', 'Usa un\'altra email', 'Ander e-mailadres gebruiken', 'Utiliser un autre e-mail'],
  'Entrar con el código': ['Entrar amb el codi', 'Entrar co código', 'Kodearekin sartu', 'Sign in with the code', 'Mit dem Code anmelden', 'Entra con il codice', 'Inloggen met de code', 'Se connecter avec le code'],
  'Hacer una foto': ['Fer una foto', 'Facer unha foto', 'Argazki bat atera', 'Take a photo', 'Foto aufnehmen', 'Scatta una foto', 'Foto maken', 'Prendre une photo'],
  'Elegir de la galería': ['Triar de la galeria', 'Escoller da galería', 'Galeriatik aukeratu', 'Choose from gallery', 'Aus Galerie wählen', 'Scegli dalla galleria', 'Kiezen uit galerij', 'Choisir dans la galerie'],
  'Quitar foto': ['Treure la foto', 'Quitar foto', 'Argazkia kendu', 'Remove photo', 'Foto entfernen', 'Rimuovi foto', 'Foto verwijderen', 'Retirer la photo'],
  'Pagar con Bizum': ['Pagar amb Bizum', 'Pagar con Bizum', 'Bizum bidez ordaindu', 'Pay with Bizum', 'Mit Bizum zahlen', 'Paga con Bizum', 'Betalen met Bizum', 'Payer avec Bizum'],
  'Ya he pagado': ['Ja he pagat', 'Xa paguei', 'Ordaindu dut', 'I\'ve paid', 'Ich habe bezahlt', 'Ho pagato', 'Ik heb betaald', 'J\'ai payé'],
  'Pagos por confirmar': ['Pagaments per confirmar', 'Pagamentos por confirmar', 'Berresteko ordainketak', 'Payments to confirm', 'Zu bestätigende Zahlungen', 'Pagamenti da confermare', 'Te bevestigen betalingen', 'Paiements à confirmer'],
  'Pendiente de que lo confirme el administrador': ['Pendent que ho confirmi l\'administrador', 'Pendente de que o confirme o administrador', 'Administratzaileak berresteko zain', 'Waiting for the admin to confirm', 'Wartet auf Bestätigung durch den Admin', 'In attesa di conferma dell\'amministratore', 'Wacht op bevestiging van de beheerder', 'En attente de confirmation par l\'administrateur'],
  'Total pendiente de cobro': ['Total pendent de cobrament', 'Total pendente de cobro', 'Kobratzeko guztira', 'Total outstanding', 'Offener Gesamtbetrag', 'Totale da incassare', 'Totaal openstaand', 'Total à encaisser'],
  'Recordar a todos los que deben': ['Recordar-ho a tots els que deuen', 'Lembrarlles a todos os que deben', 'Zorra duten guztiei gogorarazi', 'Remind everyone who owes', 'Alle Schuldner erinnern', 'Ricorda a tutti quelli che devono', 'Iedereen die schuldig is herinneren', 'Relancer tous ceux qui doivent'],
  'Sin movimientos todavía.': ['Encara no hi ha moviments.', 'Aínda non hai movementos.', 'Oraindik ez dago mugimendurik.', 'No transactions yet.', 'Noch keine Buchungen.', 'Ancora nessun movimento.', 'Nog geen transacties.', 'Aucun mouvement pour l\'instant.'],
  'Pago': ['Pagament', 'Pagamento', 'Ordainketa', 'Payment', 'Zahlung', 'Pagamento', 'Betaling', 'Paiement'],
  'Ajuste': ['Ajust', 'Axuste', 'Doikuntza', 'Adjustment', 'Korrektur', 'Rettifica', 'Correctie', 'Ajustement'],
  'Pagos': ['Pagaments', 'Pagamentos', 'Ordainketak', 'Payments', 'Zahlungen', 'Pagamenti', 'Betalingen', 'Paiements'],
  'Subir factura': ['Pujar factura', 'Subir factura', 'Faktura igo', 'Upload invoice', 'Rechnung hochladen', 'Carica fattura', 'Factuur uploaden', 'Téléverser une facture'],
  'Esta temporada': ['Aquesta temporada', 'Esta tempada', 'Denboraldi hau', 'This season', 'Diese Saison', 'Questa stagione', 'Dit seizoen', 'Cette saison'],
  'Histórico': ['Històric', 'Histórico', 'Historikoa', 'All time', 'Gesamt', 'Storico', 'Aller tijden', 'Historique'],
  'Palmarés': ['Palmarès', 'Palmarés', 'Palmaresa', 'Honours', 'Erfolge', 'Palmarès', 'Erelijst', 'Palmarès'],
  'Evolución': ['Evolució', 'Evolución', 'Bilakaera', 'Progress', 'Verlauf', 'Andamento', 'Verloop', 'Évolution'],
  'Forma y rachas': ['Forma i ratxes', 'Forma e rachas', 'Forma eta boladak', 'Form and streaks', 'Form und Serien', 'Forma e serie', 'Vorm en reeksen', 'Forme et séries'],
  'Puntos por partido': ['Punts per partit', 'Puntos por partido', 'Puntuak partidako', 'Points per match', 'Punkte pro Spiel', 'Punti per partita', 'Punten per wedstrijd', 'Points par match'],
  'Mejores parejas': ['Millors parelles', 'Mellores parellas', 'Bikote onenak', 'Best partnerships', 'Beste Duos', 'Coppie migliori', 'Beste duo\'s', 'Meilleurs duos'],
  'Mayor goleada': ['Golejada més gran', 'Maior goleada', 'Golkada handiena', 'Biggest win', 'Höchster Sieg', 'Vittoria più larga', 'Grootste overwinning', 'Plus large victoire'],
  'Partido con más goles': ['Partit amb més gols', 'Partido con máis goles', 'Gol gehien izan dituen partida', 'Highest-scoring match', 'Torreichstes Spiel', 'Partita con più gol', 'Wedstrijd met de meeste doelpunten', 'Match le plus prolifique'],
  'Los que nunca fallan': ['Els que mai fallen', 'Os que nunca fallan', 'Inoiz huts egiten ez dutenak', 'Never miss a game', 'Immer dabei', 'Quelli che non mancano mai', 'Altijd van de partij', 'Ceux qui ne ratent jamais'],
  'Clasificación final': ['Classificació final', 'Clasificación final', 'Azken sailkapena', 'Final standings', 'Abschlusstabelle', 'Classifica finale', 'Eindstand', 'Classement final'],
  'Cerrar temporada': ['Tancar la temporada', 'Pechar a tempada', 'Denboraldia itxi', 'End season', 'Saison abschließen', 'Chiudi la stagione', 'Seizoen afsluiten', 'Clôturer la saison'],
  'Reabrir la última temporada': ['Reobrir l\'última temporada', 'Reabrir a última tempada', 'Azken denboraldia berriz ireki', 'Reopen last season', 'Letzte Saison wieder öffnen', 'Riapri l\'ultima stagione', 'Laatste seizoen heropenen', 'Rouvrir la dernière saison'],
  'Bajas': ['Baixes', 'Baixas', 'Bajak', 'Absences', 'Abwesenheiten', 'Assenze', 'Afwezigheden', 'Absences'],
  'Reglamento': ['Reglament', 'Regulamento', 'Araudia', 'Rules', 'Regelwerk', 'Regolamento', 'Reglement', 'Règlement'],
  'Votaciones': ['Votacions', 'Votacións', 'Bozketak', 'Polls', 'Abstimmungen', 'Votazioni', 'Stemmingen', 'Votes'],
  'Votación': ['Votació', 'Votación', 'Bozketa', 'Poll', 'Abstimmung', 'Votazione', 'Stemming', 'Vote'],
  'Nueva votación': ['Nova votació', 'Nova votación', 'Bozketa berria', 'New poll', 'Neue Abstimmung', 'Nuova votazione', 'Nieuwe stemming', 'Nouveau vote'],
  'Abiertas': ['Obertes', 'Abertas', 'Irekiak', 'Open', 'Offen', 'Aperte', 'Open', 'Ouverts'],
  'Cerradas': ['Tancades', 'Pechadas', 'Itxiak', 'Closed', 'Geschlossen', 'Chiuse', 'Gesloten', 'Clos'],
  'Abrir votación': ['Obrir la votació', 'Abrir votación', 'Bozketa ireki', 'Open poll', 'Abstimmung starten', 'Apri la votazione', 'Stemming openen', 'Ouvrir le vote'],
  'Abrir encuesta general': ['Obrir enquesta general', 'Abrir enquisa xeral', 'Inkesta orokorra ireki', 'Open general survey', 'Allgemeine Umfrage starten', 'Apri sondaggio generale', 'Algemene enquête openen', 'Ouvrir un sondage général'],
  'Encuesta de día y hora': ['Enquesta de dia i hora', 'Enquisa de día e hora', 'Egun eta orduaren inkesta', 'Date and time poll', 'Termin-Umfrage', 'Sondaggio su giorno e ora', 'Datumprikker', 'Sondage date et heure'],
  'Añadir día y hora': ['Afegir dia i hora', 'Engadir día e hora', 'Eguna eta ordua gehitu', 'Add date and time', 'Datum und Uhrzeit hinzufügen', 'Aggiungi giorno e ora', 'Datum en tijd toevoegen', 'Ajouter date et heure'],
  'Añadir opción': ['Afegir opció', 'Engadir opción', 'Aukera gehitu', 'Add option', 'Option hinzufügen', 'Aggiungi opzione', 'Optie toevoegen', 'Ajouter une option'],
  'Voto anónimo': ['Vot anònim', 'Voto anónimo', 'Boto anonimoa', 'Anonymous vote', 'Anonyme Abstimmung', 'Voto anonimo', 'Anonieme stem', 'Vote anonyme'],
  'Duración': ['Durada', 'Duración', 'Iraupena', 'Duration', 'Dauer', 'Durata', 'Duur', 'Durée'],
  'Cerrar ya': ['Tancar ara', 'Pechar xa', 'Orain itxi', 'Close now', 'Jetzt schließen', 'Chiudi ora', 'Nu sluiten', 'Clôturer maintenant'],
  'Cancelar votación': ['Cancel·lar la votació', 'Cancelar votación', 'Bozketa bertan behera utzi', 'Cancel poll', 'Abstimmung abbrechen', 'Annulla votazione', 'Stemming annuleren', 'Annuler le vote'],
  'Mejor, que vote la liga': ['Millor, que voti la lliga', 'Mellor, que vote a liga', 'Hobe, liga bozka dezala', 'Let the league vote', 'Lieber die Liga abstimmen lassen', 'Meglio far votare la lega', 'Laat de competitie stemmen', 'Mieux vaut faire voter la ligue'],
  'Guardar cambio': ['Desar el canvi', 'Gardar cambio', 'Aldaketa gorde', 'Save change', 'Änderung speichern', 'Salva modifica', 'Wijziging opslaan', 'Enregistrer la modification'],
  'Volver al valor estándar': ['Tornar al valor estàndard', 'Volver ao valor estándar', 'Balio estandarrera itzuli', 'Reset to standard', 'Auf Standard zurücksetzen', 'Ripristina valore standard', 'Standaardwaarde herstellen', 'Revenir à la valeur standard'],
  'Otras normas acordadas (texto libre)': ['Altres normes acordades (text lliure)', 'Outras normas acordadas (texto libre)', 'Adostutako beste arau batzuk (testu librea)', 'Other agreed rules (free text)', 'Weitere vereinbarte Regeln (Freitext)', 'Altre regole concordate (testo libero)', 'Andere afgesproken regels (vrije tekst)', 'Autres règles convenues (texte libre)'],
  'Modalidad': ['Modalitat', 'Modalidade', 'Modalitatea', 'Format', 'Spielform', 'Modalità', 'Spelvorm', 'Format'],
  'Asistencia y bajas': ['Assistència i baixes', 'Asistencia e baixas', 'Asistentzia eta bajak', 'Attendance and absences', 'Teilnahme und Abwesenheiten', 'Presenze e assenze', 'Aanwezigheid en afwezigheid', 'Présences et absences'],
  'Baja temporal': ['Baixa temporal', 'Baixa temporal', 'Aldi baterako baja', 'Temporary absence', 'Vorübergehende Abwesenheit', 'Assenza temporanea', 'Tijdelijke afwezigheid', 'Absence temporaire'],
  'Añadir baja': ['Afegir baixa', 'Engadir baixa', 'Baja gehitu', 'Add absence', 'Abwesenheit hinzufügen', 'Aggiungi assenza', 'Afwezigheid toevoegen', 'Ajouter une absence'],
  'Ha vuelto': ['Ha tornat', 'Volveu', 'Itzuli da', 'Is back', 'Ist zurück', 'È tornato', 'Is terug', 'Est revenu'],
  'Ninguna registrada.': ['Cap de registrada.', 'Ningunha rexistrada.', 'Bat ere ez erregistratuta.', 'None recorded.', 'Keine erfasst.', 'Nessuna registrata.', 'Geen geregistreerd.', 'Aucune enregistrée.'],
  'Desde': ['Des de', 'Desde', 'Noiztik', 'From', 'Ab', 'Dal', 'Vanaf', 'Depuis'],
  'Vuelve': ['Torna', 'Volve', 'Itzuliko da', 'Back on', 'Zurück am', 'Torna', 'Terug op', 'Retour'],
  'Sin fecha': ['Sense data', 'Sen data', 'Datarik gabe', 'No date', 'Ohne Datum', 'Senza data', 'Geen datum', 'Sans date'],
  'Ajustes de la liga': ['Configuració de la lliga', 'Axustes da liga', 'Ligaren ezarpenak', 'League settings', 'Liga-Einstellungen', 'Impostazioni della lega', 'Competitie-instellingen', 'Paramètres de la ligue'],
  'Convocatoria y cobro': ['Convocatòria i cobrament', 'Convocatoria e cobro', 'Deialdia eta kobrantza', 'Line-up and payments', 'Aufstellung und Bezahlung', 'Convocazione e pagamenti', 'Opstelling en betaling', 'Convocation et paiement'],
  'Equipaciones': ['Equipacions', 'Equipacións', 'Ekipazioak', 'Kits', 'Trikots', 'Divise', 'Tenues', 'Maillots'],
  'Exportar a Excel': ['Exportar a Excel', 'Exportar a Excel', 'Excelera esportatu', 'Export to Excel', 'Nach Excel exportieren', 'Esporta in Excel', 'Exporteren naar Excel', 'Exporter vers Excel'],
  'Programar temporada': ['Programar temporada', 'Programar tempada', 'Denboraldia programatu', 'Schedule season', 'Saison planen', 'Programma la stagione', 'Seizoen plannen', 'Planifier la saison'],
  'Normas de la liga': ['Normes de la lliga', 'Normas da liga', 'Ligaren arauak', 'League rules', 'Liga-Regeln', 'Regole della lega', 'Competitieregels', 'Règles de la ligue'],
  'Invita al grupo': ['Convida el grup', 'Convida o grupo', 'Taldea gonbidatu', 'Invite the group', 'Lade die Gruppe ein', 'Invita il gruppo', 'Nodig de groep uit', 'Invite le groupe'],
  'Compartir invitación': ['Compartir la invitació', 'Compartir invitación', 'Gonbidapena partekatu', 'Share invitation', 'Einladung teilen', 'Condividi invito', 'Uitnodiging delen', 'Partager l\'invitation'],
  'Crear el primer partido': ['Crear el primer partit', 'Crear o primeiro partido', 'Lehen partida sortu', 'Create the first match', 'Erstes Spiel erstellen', 'Crea la prima partita', 'Eerste wedstrijd aanmaken', 'Créer le premier match'],
  'Yo también soy fijo': ['Jo també soc fix', 'Eu tamén son fixo', 'Ni ere finkoa naiz', 'I\'m a regular too', 'Ich bin auch Stammspieler', 'Anch\'io sono fisso', 'Ik ben ook vaste speler', 'Je suis aussi titulaire'],
  'Enviar por WhatsApp': ['Enviar per WhatsApp', 'Enviar por WhatsApp', 'WhatsApp bidez bidali', 'Send via WhatsApp', 'Per WhatsApp senden', 'Invia su WhatsApp', 'Versturen via WhatsApp', 'Envoyer par WhatsApp'],
  'Otras apps': ['Altres apps', 'Outras apps', 'Beste aplikazio batzuk', 'Other apps', 'Andere Apps', 'Altre app', 'Andere apps', 'Autres applis'],
  'Como imagen': ['Com a imatge', 'Como imaxe', 'Irudi gisa', 'As an image', 'Als Bild', 'Come immagine', 'Als afbeelding', 'En image'],
  'Compartir imagen': ['Compartir la imatge', 'Compartir imaxe', 'Irudia partekatu', 'Share image', 'Bild teilen', 'Condividi immagine', 'Afbeelding delen', 'Partager l\'image'],
  'Para el grupo o Instagram': ['Per al grup o Instagram', 'Para o grupo ou Instagram', 'Talderako edo Instagramerako', 'For the group or Instagram', 'Für die Gruppe oder Instagram', 'Per il gruppo o Instagram', 'Voor de groep of Instagram', 'Pour le groupe ou Instagram'],
  'Partidos en tu calendario': ['Partits al teu calendari', 'Partidos no teu calendario', 'Partidak zure egutegian', 'Matches in your calendar', 'Spiele in deinem Kalender', 'Partite nel tuo calendario', 'Wedstrijden in je agenda', 'Matchs dans ton agenda'],
  'Copiar enlace': ['Copiar l\'enllaç', 'Copiar ligazón', 'Esteka kopiatu', 'Copy link', 'Link kopieren', 'Copia link', 'Link kopiëren', 'Copier le lien'],
  'Google Calendar': ['Google Calendar', 'Google Calendar', 'Google Calendar', 'Google Calendar', 'Google Kalender', 'Google Calendar', 'Google Agenda', 'Google Agenda'],
  'iPhone, Mac u Outlook': ['iPhone, Mac o Outlook', 'iPhone, Mac ou Outlook', 'iPhone, Mac edo Outlook', 'iPhone, Mac or Outlook', 'iPhone, Mac oder Outlook', 'iPhone, Mac o Outlook', 'iPhone, Mac of Outlook', 'iPhone, Mac ou Outlook'],
  'Solo descargar los próximos (.ics)': ['Només baixar els propers (.ics)', 'Só descargar os próximos (.ics)', 'Hurrengoak soilik deskargatu (.ics)', 'Just download upcoming (.ics)', 'Nur kommende herunterladen (.ics)', 'Scarica solo i prossimi (.ics)', 'Alleen komende downloaden (.ics)', 'Télécharger seulement les prochains (.ics)'],
  'Otro calendario (archivo .ics)': ['Un altre calendari (fitxer .ics)', 'Outro calendario (ficheiro .ics)', 'Beste egutegi bat (.ics fitxategia)', 'Other calendar (.ics file)', 'Anderer Kalender (.ics-Datei)', 'Altro calendario (file .ics)', 'Andere agenda (.ics-bestand)', 'Autre agenda (fichier .ics)'],
  'Plantilla': ['Plantilla', 'Persoal', 'Plantila', 'Squad', 'Kader', 'Rosa', 'Selectie', 'Effectif'],
  'Alineación': ['Alineació', 'Aliñación', 'Hamaikakoa', 'Line-up', 'Aufstellung', 'Formazione', 'Opstelling', 'Composition'],
  'Guardar alineación': ['Desar l\'alineació', 'Gardar aliñación', 'Hamaikakoa gorde', 'Save line-up', 'Aufstellung speichern', 'Salva formazione', 'Opstelling opslaan', 'Enregistrer la composition'],
  'Valor de mercado': ['Valor de mercat', 'Valor de mercado', 'Merkatu-balioa', 'Market value', 'Marktwert', 'Valore di mercato', 'Marktwaarde', 'Valeur marchande'],
  'Hacer oferta': ['Fer oferta', 'Facer oferta', 'Eskaintza egin', 'Make an offer', 'Angebot machen', 'Fai un\'offerta', 'Bod uitbrengen', 'Faire une offre'],
  'Vender al mercado': ['Vendre al mercat', 'Vender ao mercado', 'Merkatuari saldu', 'Sell to market', 'An den Markt verkaufen', 'Vendi al mercato', 'Verkopen aan de markt', 'Vendre au marché'],
  'Pagar cláusula': ['Pagar la clàusula', 'Pagar cláusula', 'Klausula ordaindu', 'Pay release clause', 'Ausstiegsklausel zahlen', 'Paga la clausola', 'Afkoopsom betalen', 'Payer la clause'],
  'Ofertas recibidas': ['Ofertes rebudes', 'Ofertas recibidas', 'Jasotako eskaintzak', 'Offers received', 'Erhaltene Angebote', 'Offerte ricevute', 'Ontvangen biedingen', 'Offres reçues'],
  'Ofertas enviadas': ['Ofertes enviades', 'Ofertas enviadas', 'Bidalitako eskaintzak', 'Offers sent', 'Gesendete Angebote', 'Offerte inviate', 'Verstuurde biedingen', 'Offres envoyées'],
  'Mercado cerrado': ['Mercat tancat', 'Mercado pechado', 'Merkatua itxita', 'Market closed', 'Markt geschlossen', 'Mercato chiuso', 'Markt gesloten', 'Marché fermé'],
  'Puntos Fantasy': ['Punts Fantasy', 'Puntos Fantasy', 'Fantasy puntuak', 'Fantasy points', 'Fantasy-Punkte', 'Punti Fantasy', 'Fantasy-punten', 'Points Fantasy'],
  'Tus puntos de mánager': ['Els teus punts de mànager', 'Os teus puntos de mánager', 'Zure manager-puntuak', 'Your manager points', 'Deine Manager-Punkte', 'I tuoi punti manager', 'Jouw managerpunten', 'Tes points de manager'],
  'Reiniciar Fantasy': ['Reiniciar el Fantasy', 'Reiniciar Fantasy', 'Fantasy berrabiarazi', 'Reset Fantasy', 'Fantasy zurücksetzen', 'Riavvia Fantasy', 'Fantasy opnieuw starten', 'Réinitialiser le Fantasy'],
};
