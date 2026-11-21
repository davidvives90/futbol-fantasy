-- 0041 · Nuevo estado de inscripción: «pendiente» (fijo apuntado solo, falta que confirme).
-- Va en su propia migración: un valor nuevo de un enum no se puede usar en la misma transacción.
alter type estado_inscr add value if not exists 'pendiente';
