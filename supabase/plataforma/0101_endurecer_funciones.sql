alter function media_general(posicion_campo, numeric, numeric, numeric, numeric, numeric, numeric) set search_path = public;
alter function redondear_005(numeric) set search_path = public;
alter function puntos_por_nota(numeric, numeric) set search_path = public;
alter function consenso(smallint[], boolean) set search_path = public;
revoke execute on function nota_partido(uuid, uuid), valor_resuelto(uuid, text, smallint, uuid, text),
                           puede_reportar(uuid, uuid), jugo_partido(uuid, uuid) from authenticated;
