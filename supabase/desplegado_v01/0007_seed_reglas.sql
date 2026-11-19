-- 0007 · Valores por defecto de cada liga nueva: reglas de puntuación y aspectos de valoración
-- Inspirado en el sistema de LaLiga Fantasy MARCA (ver docs/puntuacion_fantasy.md), adaptado a fútbol amateur.

create or replace function sembrar_liga_defecto(p_liga uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  insert into reglas_puntuacion (liga_id, clave, puntos) values
    (p_liga, 'jugado',                  2),
    (p_liga, 'victoria',                3),   -- por encuentro ganado
    (p_liga, 'empate',                  1),
    (p_liga, 'gol_portero',             6),   -- si ligas.puntuar_por_posicion
    (p_liga, 'gol_defensa',             6),
    (p_liga, 'gol_medio',               5),
    (p_liga, 'gol_delantero',           4),
    (p_liga, 'gol',                     4),   -- sin posición o liga sin puntuación por posición
    (p_liga, 'asistencia',              3),
    (p_liga, 'porteria_cero_portero',   4),   -- por encuentro sin encajar
    (p_liga, 'porteria_cero_defensa',   2),
    (p_liga, 'goles_encajados_3',      -1),   -- portero, por cada 3 encajados
    (p_liga, 'parada_clave_2',          1),   -- por cada 2 paradas clave
    (p_liga, 'penalti_parado',          3),
    (p_liga, 'penalti_fallado',        -2),
    (p_liga, 'autogol',                -2),
    (p_liga, 'valoracion_max',          4),   -- tope de puntos por nota de compañeros
    (p_liga, 'mvp',                     3)
  on conflict do nothing;

  insert into aspectos_valoracion (liga_id, clave, nombre, descripcion, orden, aplica_a) values
    (p_liga, 'ataque',       'Ataque',          'Peligro, regate, remate y desmarque',            1, 'campo'),
    (p_liga, 'porteria',     'Portería',        'Paradas, salidas y colocación',                  1, 'porteros'),
    (p_liga, 'defensa',      'Defensa',         'Recuperaciones, marcaje, ayudas atrás',          2, 'todos'),
    (p_liga, 'pase_vision',  'Pase y visión',   'Precisión, último pase, hacer jugar al equipo',  3, 'todos'),
    (p_liga, 'esfuerzo',     'Esfuerzo',        'Intensidad, presión y compromiso',               4, 'todos'),
    (p_liga, 'juego_limpio', 'Juego limpio',    'Deportividad y respeto',                         5, 'todos')
  on conflict do nothing;
end $$;

revoke execute on function sembrar_liga_defecto(uuid) from public, anon, authenticated;
