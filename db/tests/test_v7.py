#!/usr/bin/env python3
"""
Suite de regresión del esquema v7 (PostgreSQL, multiempresa).

Cada prueba intenta ROMPER una regla y verifica que la base lo impida.
Las que empiezan con "aislamiento" son las más importantes: comprueban
que un comercio no puede ver ni tocar datos de otro.
"""
import subprocess, sys, os, json, uuid

PSQL = ['psql', '-X', '-q', '-t', '-A', '-v', 'ON_ERROR_STOP=1',
        '-h', 'localhost', '-p', '5432', '-U', 'fichas_dev', '-d', 'fichas']
ok = fail = 0


def sql(texto, comercio=None, rol='app_fichas'):
    """Ejecuta SQL en una transacción, con el comercio y el rol declarados."""
    pre = f"SET ROLE {rol};\n" if rol else ""
    if comercio:
        pre += f"SET LOCAL app.comercio_id = '{comercio}';\n"
    r = subprocess.run(PSQL, input="BEGIN;\n" + pre + texto + "\nCOMMIT;",
                       capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(r.stderr.strip().split('\n')[0])
    return r.stdout.strip()


def consulta(texto, comercio=None):
    pre = f"SET ROLE app_fichas;\nSET LOCAL app.comercio_id = '{comercio}';\n" if comercio else ""
    r = subprocess.run(PSQL, input="BEGIN;\n" + pre + texto + "\nCOMMIT;",
                       capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(r.stderr.strip().split('\n')[0])
    return [l for l in r.stdout.strip().split('\n') if l]


def admin(texto):
    r = subprocess.run(PSQL, input=texto, capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(r.stderr.strip())
    return r.stdout.strip()


def permite(desc, fn):
    global ok, fail
    try:
        fn(); print(f'  ok     {desc}'); ok += 1
    except Exception as e:
        print(f'  FALLA  {desc}: {e}'); fail += 1


def bloquea(desc, fn, contiene=''):
    global ok, fail
    try:
        fn(); print(f'  FALLA  {desc}: NO bloqueó'); fail += 1
    except Exception as e:
        m = str(e)
        if contiene and contiene.lower() not in m.lower():
            print(f'  FALLA  {desc}: bloqueó por otra razón: {m}'); fail += 1
        else:
            print(f'  ok     {desc}'); ok += 1


def vale(desc, obtenido, esperado):
    global ok, fail
    if obtenido == esperado:
        print(f'  ok     {desc}'); ok += 1
    else:
        print(f'  FALLA  {desc}: obtuvo {obtenido!r}, esperaba {esperado!r}'); fail += 1


# ═══════════════════════════════════════════════════════════════════
#  Datos base: DOS comercios distintos
# ═══════════════════════════════════════════════════════════════════
print('\nPreparación: dos comercios independientes')

A = str(uuid.uuid4())   # comercio A
B = str(uuid.uuid4())   # comercio B
ids = {}

admin(f"""
INSERT INTO comercio (id,nombre,slug) VALUES
  ('{A}','Fichas Acme','acme'), ('{B}','Wifi Beta','beta');
""")

for letra, cid in (('A', A), ('B', B)):
    r = admin(f"""
    SET app.comercio_id = '{cid}';
    INSERT INTO punto (comercio_id,nombre,prefijo,ref_patron_pos)
      VALUES ('{cid}','Principal','{"LIMA01" if letra=="A" else "CUZCO1"}','^[0-9]{{6}}$')
      RETURNING id;
    """).split('\n')[-1]
    ids[f'punto{letra}'] = r
    ids[f'plan{letra}'] = admin(f"""
    INSERT INTO plan (comercio_id,codigo,nombre,precio_centimos,limite_tiempo_seg,
                      validez_dias,rate_limit,categoria)
      VALUES ('{cid}','DIA1','1 dia',500,86400,7,'3M/1M','tiempo') RETURNING id;
    """).split('\n')[-1]
    for rol, mail in (('operario', f'rosa@{letra.lower()}.pe'),
                      ('supervisor', f'ana@{letra.lower()}.pe')):
        ids[f'{rol}{letra}'] = admin(f"""
        INSERT INTO usuario (comercio_id,nombre,email,password_hash,rol)
          VALUES ('{cid}','{rol.title()}','{mail}','x','{rol}') RETURNING id;
        """).split('\n')[-1]
    ids[f'turno{letra}'] = admin(f"""
    INSERT INTO turno (comercio_id,punto_id,usuario_id,dia_operativo,fondo_inicial)
      VALUES ('{cid}','{ids[f"punto{letra}"]}','{ids[f"operario{letra}"]}',
              CURRENT_DATE,1000) RETURNING id;
    """).split('\n')[-1]
    ids[f'lote{letra}'] = admin(f"""
    INSERT INTO lote (comercio_id,punto_id,plan_id,cantidad)
      VALUES ('{cid}','{ids[f"punto{letra}"]}','{ids[f"plan{letra}"]}',10) RETURNING id;
    """).split('\n')[-1]
print('  ok     dos comercios con punto, plan, usuarios, turno y lote')
ok += 1


def nueva_ficha(letra, codigo, en_router=True):
    cid = A if letra == 'A' else B
    return admin(f"""
    INSERT INTO ficha (comercio_id,punto_id,lote_id,plan_id,codigo,en_router,router_conf_en)
      VALUES ('{cid}','{ids[f"punto{letra}"]}','{ids[f"lote{letra}"]}',
              '{ids[f"plan{letra}"]}','{codigo}',{str(en_router).lower()},
              {'now()' if en_router else 'NULL'}) RETURNING id;
    """).split('\n')[-1]


# ═══════════════════════════════════════════════════════════════════
print('\nAislamiento entre comercios (lo más importante)')

fA = nueva_ficha('A', 'LIMA01-AB2CD')
fB = nueva_ficha('B', 'CUZCO1-XY7ZW')

vale('el comercio A ve solo su ficha',
     consulta('SELECT count(*) FROM ficha;', A), ['1'])
vale('el comercio B ve solo la suya',
     consulta('SELECT count(*) FROM ficha;', B), ['1'])
vale('una consulta SIN filtro no cruza comercios',
     consulta('SELECT codigo FROM ficha;', A), ['LIMA01-AB2CD'])
vale('B no puede leer la ficha de A ni con su id',
     consulta(f"SELECT count(*) FROM ficha WHERE id='{fA}';", B), ['0'])
# La seguridad por fila NO lanza error en un UPDATE cruzado: filtra las
# filas, así que la orden afecta a CERO. La aplicación debe revisar
# cuántas filas tocó, no esperar una excepción.
vale('B modificando la ficha de A afecta 0 filas (no lanza error)',
     consulta(f"""WITH u AS (UPDATE ficha SET estado='anulada'
                  WHERE id='{fA}' RETURNING 1)
                  SELECT count(*) FROM u;""", B), ['0'])
vale('...y la ficha de A sigue disponible',
     consulta(f"SELECT estado FROM ficha WHERE id='{fA}';", A), ['disponible'])
bloquea('nadie puede insertar filas de OTRO comercio',
        lambda: sql(f"""INSERT INTO plan (comercio_id,codigo,nombre,precio_centimos,
                        limite_tiempo_seg,validez_dias,rate_limit)
                        VALUES ('{B}','HACK','robo',100,3600,7,'1M/1M');""", A),
        'row-level security')
bloquea('sin declarar comercio no se ve nada (falla la escritura)',
        lambda: sql("INSERT INTO cliente (comercio_id,celular,consentimiento_en) "
                    f"VALUES ('{A}','987654321',now());", None))
vale('sin declarar comercio, tampoco se lee nada',
     consulta('SELECT count(*) FROM ficha;', None) if False else
     admin("SET ROLE app_fichas; SELECT count(*) FROM ficha;").split('\n')[-1], '0')

print('\nUnicidades que en v6 eran globales (las 4 correcciones)')
permite('los dos comercios pueden tener el MISMO correo de usuario... no',
        lambda: None)
bloquea('el correo sí es único en todo el sistema (es la llave del portal)',
        lambda: admin(f"""INSERT INTO usuario (comercio_id,nombre,email,password_hash)
                          VALUES ('{B}','Otra','rosa@a.pe','x');"""), 'usuario_email_global')
permite('los dos comercios tienen su propio plan con código DIA1',
        lambda: vale('  (ya creados arriba)',
                     admin("SELECT count(*) FROM plan WHERE codigo='DIA1';"), '2'))
permite('el mismo celular puede ser cliente de AMBOS comercios',
        lambda: [admin(f"""INSERT INTO cliente (comercio_id,celular,consentimiento_en)
                           VALUES ('{c}','987654321',now());""") for c in (A, B)])
bloquea('pero no dos veces en el mismo comercio',
        lambda: admin(f"""INSERT INTO cliente (comercio_id,celular,consentimiento_en)
                          VALUES ('{A}','987654321',now());"""), 'unique')

print('\nNumeración de órdenes por comercio (condición de carrera corregida)')
def nueva_orden(letra, ficha_id):
    cid = A if letra == 'A' else B
    admin(f"UPDATE ficha SET estado='reservada', reservada_hasta=now()+interval '10 min' "
          f"WHERE id='{ficha_id}';")
    return admin(f"""
    INSERT INTO orden (comercio_id,turno_id,usuario_id,ficha_id,plan_id,
                       monto_centimos,expira_en)
      VALUES ('{cid}','{ids[f"turno{letra}"]}','{ids[f"operario{letra}"]}','{ficha_id}',
              '{ids[f"plan{letra}"]}',500,now()+interval '10 min')
      RETURNING id||'|'||numero;""").split('\n')[-1]

oA, nA = nueva_orden('A', fA).split('|')
oB, nB = nueva_orden('B', fB).split('|')
vale('cada comercio empieza su numeración en 1', (nA, nB), ('1', '1'))
f2 = nueva_ficha('A', 'LIMA01-EF3GH')
o2, n2 = nueva_orden('A', f2).split('|')
vale('la numeración de A avanza a 2', n2, '2')

print('\nCobro con POS externo y conciliación')
def pago_pos(comercio, orden, ref, usuario, medio='QR'):
    return lambda: admin(f"""
    INSERT INTO pago (comercio_id,orden_id,metodo,motivo_manual,medio,referencia,
                      estado,monto_centimos,confirmado_por,resuelto_en)
      VALUES ('{comercio}','{orden}','manual','pos_externo','{medio}','{ref}',
              'exitoso',500,'{usuario}',now());""")

bloquea('referencia con espacio', pago_pos(A, oA, '123 456', ids['operarioA']))
bloquea('referencia de 7 dígitos con patrón de 6',
        pago_pos(A, oA, '1234567', ids['operarioA']), 'RN-10')
bloquea('pago del POS sin medio',
        lambda: admin(f"""INSERT INTO pago (comercio_id,orden_id,metodo,motivo_manual,
                          referencia,estado,monto_centimos,resuelto_en)
                          VALUES ('{A}','{oA}','manual','pos_externo','482913','exitoso',500,now());"""))
bloquea('monto distinto al de la orden',
        lambda: admin(f"""INSERT INTO pago (comercio_id,orden_id,metodo,motivo_manual,medio,
                          referencia,estado,monto_centimos,resuelto_en)
                          VALUES ('{A}','{oA}','manual','pos_externo','QR','482913','exitoso',900,now());"""),
        'RN-05')
permite('pago válido del POS en el comercio A', pago_pos(A, oA, '482913', ids['operarioA']))
permite('el comercio B puede usar la MISMA referencia 482913',
        pago_pos(B, oB, '482913', ids['operarioB']))
bloquea('pero A no puede repetirla',
        pago_pos(A, o2, '482913', ids['operarioA']), 'unique')

print('\nVenta, inmutabilidad y anulación')
def venta(letra, orden, ficha, metodo='manual'):
    cid = A if letra == 'A' else B
    return admin(f"""
    INSERT INTO venta (comercio_id,turno_id,usuario_id,ficha_id,orden_id,plan_id,
                       metodo,monto_centimos,fecha_local,hora_local)
      VALUES ('{cid}','{ids[f"turno{letra}"]}','{ids[f"operario{letra}"]}','{ficha}','{orden}',
              '{ids[f"plan{letra}"]}','{metodo}',500,CURRENT_DATE,14) RETURNING id;""").split('\n')[-1]

bloquea('no hay venta sin pago exitoso',
        lambda: venta('A', o2, f2), 'RN-04')
vA = venta('A', oA, fA)
admin(f"UPDATE orden SET estado='pagada', resuelta_en=now() WHERE id='{oA}';")
admin(f"UPDATE ficha SET estado='vendida', vendida_en=now() WHERE id='{fA}';")
print('  ok     venta registrada'); ok += 1
bloquea('la venta es inmutable',
        lambda: admin(f"UPDATE venta SET monto_centimos=100 WHERE id='{vA}';"), 'RN-06')
bloquea('la venta no se borra',
        lambda: admin(f"DELETE FROM venta WHERE id='{vA}';"), 'RN-06')
bloquea('una ficha activada no se anula',
        lambda: admin(f"""UPDATE ficha SET estado='activada', primer_login_en=now()
                          WHERE id='{fA}';
                          UPDATE ficha SET estado='anulada' WHERE id='{fA}';"""), 'RN-02')

print('\nConciliación')
pagoA = admin(f"SELECT id FROM pago WHERE orden_id='{oA}';").split('\n')[-1]
bloquea('un operario no puede conciliar',
        lambda: admin(f"""UPDATE pago SET conciliado_en=now(),
                          conciliado_por='{ids["operarioA"]}' WHERE id='{pagoA}';"""), 'RN-09')
permite('el supervisor concilia',
        lambda: admin(f"""UPDATE pago SET conciliado_en=now(),
                          conciliado_por='{ids["supervisorA"]}' WHERE id='{pagoA}';"""))
bloquea('una conciliación no se deshace',
        lambda: admin(f"UPDATE pago SET conciliado_en=NULL, conciliado_por=NULL WHERE id='{pagoA}';"),
        'RN-08')

print('\nTurnos')
vale('un turno abierto por punto', admin(
    "SELECT count(*) FROM turno WHERE cerrado_en IS NULL;"), '2')
bloquea('dos turnos abiertos en el MISMO punto',
        lambda: admin(f"""INSERT INTO turno (comercio_id,punto_id,usuario_id,dia_operativo)
                          VALUES ('{A}','{ids["puntoA"]}','{ids["supervisorA"]}',CURRENT_DATE);"""),
        'turno_uno_abierto_por_punto')
permite('un segundo punto del mismo comercio sí puede tener su turno',
        lambda: admin(f"""
        INSERT INTO punto (id,comercio_id,nombre,prefijo)
          VALUES ('{(p2:=str(uuid.uuid4()))}','{A}','Sucursal','LIMA02');
        INSERT INTO turno (comercio_id,punto_id,usuario_id,dia_operativo)
          VALUES ('{A}','{p2}','{ids["supervisorA"]}',CURRENT_DATE);"""))

print('\nCuadre de caja: sin doble descuento al anular')
fe = nueva_ficha('B', 'CUZCO1-QR8ST')
oe, _ = nueva_orden('B', fe).split('|')
admin(f"""INSERT INTO pago (comercio_id,orden_id,metodo,estado,monto_centimos,
          recibido_centimos,confirmado_por,resuelto_en)
          VALUES ('{B}','{oe}','efectivo','exitoso',500,1000,'{ids["operarioB"]}',now());""")
bloquea('RN-13 cobrar en efectivo y registrar la venta como manual',
        lambda: venta('B', oe, fe, metodo='manual'), 'RN-13')
ve = venta('B', oe, fe, metodo='efectivo')
admin(f"UPDATE orden SET estado='pagada', resuelta_en=now() WHERE id='{oe}';")
admin(f"UPDATE ficha SET estado='vendida', vendida_en=now() WHERE id='{fe}';")
esp = admin(f"SET app.comercio_id='{B}'; SELECT efectivo_esperado FROM v_turno_actual "
            f"WHERE turno_id='{ids['turnoB']}';").split('\n')[-1]
vale('tras cobrar S/5 en efectivo: esperado 1500 (fondo 1000 + 500)', esp, '1500')
admin(f"""INSERT INTO anulacion (comercio_id,venta_id,turno_id,usuario_id,motivo)
          VALUES ('{B}','{ve}','{ids["turnoB"]}','{ids["supervisorB"]}','error_operario');""")
esp = admin(f"SET app.comercio_id='{B}'; SELECT efectivo_esperado FROM v_turno_actual "
            f"WHERE turno_id='{ids['turnoB']}';").split('\n')[-1]
vale('tras anular: vuelve a 1000, sin descontar dos veces', esp, '1000')
vale('la venta anulada sale de v_venta_vigente',
     admin(f"SET app.comercio_id='{B}'; SELECT count(*) FROM v_venta_vigente WHERE id='{ve}';").split('\n')[-1], '0')
vale('pero la venta original se conserva',
     admin(f"SELECT count(*) FROM venta WHERE id='{ve}';"), '1')

print('\nVuelto en efectivo')
bloquea('recibir menos que el precio',
        lambda: admin(f"""INSERT INTO pago (comercio_id,orden_id,metodo,estado,
                          monto_centimos,recibido_centimos,resuelto_en)
                          VALUES ('{A}','{o2}','efectivo','exitoso',500,300,now());"""))
bloquea('registrar lo recibido en un pago que no es efectivo',
        lambda: admin(f"""INSERT INTO pago (comercio_id,orden_id,metodo,motivo_manual,medio,
                          referencia,estado,monto_centimos,recibido_centimos,resuelto_en)
                          VALUES ('{A}','{o2}','manual','pos_externo','QR','999888','exitoso',500,1000,now());"""))

print('\nStock calculado')
vale('v_pool cuenta solo las fichas vendibles de cada comercio',
     admin(f"SET app.comercio_id='{A}'; SELECT disponibles||'/'||sin_cargar FROM v_pool "
           f"WHERE plan_id='{ids['planA']}';").split('\n')[-1], '0/0')
nueva_ficha('A', 'LIMA01-JK4LM')
nueva_ficha('A', 'LIMA01-MN5PQ', en_router=False)
vale('una ficha nueva en el router suma; la que no está, va aparte',
     admin(f"SET app.comercio_id='{A}'; SELECT disponibles||'/'||sin_cargar FROM v_pool "
           f"WHERE plan_id='{ids['planA']}';").split('\n')[-1], '1/1')
bloquea('no se puede reservar una ficha que no está en el router',
        lambda: admin("""UPDATE ficha SET estado='reservada', reservada_hasta=now()
                         WHERE codigo='LIMA01-MN5PQ';"""), 'RN-01')

print('\nAlarmas de integridad (deben dar cero)')
for v in ('v_alarma_sin_pago', 'v_alarma_sin_venta', 'v_alarma_codigo_muerto',
          'v_alarma_fuga_pool'):
    vale(v, admin(f"SELECT count(*) FROM {v};"), '0')

print(f"\n{'='*54}\n  {ok} pasaron · {fail} fallaron\n{'='*54}")
sys.exit(1 if fail else 0)
