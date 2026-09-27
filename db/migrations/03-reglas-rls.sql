-- ═══════════════════════════════════════════════════════════════════════
--  REGLAS DE NEGOCIO QUE IMPONE LA BASE
--
--  La aplicación puede tener errores, reintentos por mala señal, o dos
--  pestañas actuando a la vez. La base no. Si una regla puede provocar
--  un descuadre, la hace cumplir la base.
-- ═══════════════════════════════════════════════════════════════════════

-- RN-01 · Solo se reserva una ficha CONFIRMADA en el router.
-- Una ficha que no está en el router es un código muerto: venderla
-- significa cobrarle a alguien por algo que no funciona.
CREATE FUNCTION f_ficha_transicion() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.estado = 'reservada' AND OLD.estado = 'disponible'
       AND NOT NEW.en_router THEN
        RAISE EXCEPTION 'RN-01: la ficha no esta confirmada en el router';
    END IF;

    -- RN-02 · Solo transiciones válidas del ciclo de vida.
    IF NEW.estado IS DISTINCT FROM OLD.estado AND NOT (
           (OLD.estado = 'disponible' AND NEW.estado IN ('reservada','anulada'))
        OR (OLD.estado = 'reservada'  AND NEW.estado IN ('disponible','vendida'))
        OR (OLD.estado = 'vendida'    AND NEW.estado IN ('activada','expirada','anulada'))
        OR (OLD.estado = 'activada'   AND NEW.estado IN ('agotada','expirada'))
    ) THEN
        RAISE EXCEPTION 'RN-02: transicion invalida % -> %', OLD.estado, NEW.estado;
    END IF;

    -- El código y el lote no cambian nunca.
    IF NEW.codigo <> OLD.codigo OR NEW.lote_id <> OLD.lote_id THEN
        RAISE EXCEPTION 'RN-03: el codigo y el lote de una ficha son inmutables';
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_ficha_transicion BEFORE UPDATE ON ficha
    FOR EACH ROW EXECUTE FUNCTION f_ficha_transicion();


-- RN-04 · No hay venta sin dinero: la orden necesita un pago exitoso.
CREATE FUNCTION f_venta_exige_pago() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pago
                   WHERE orden_id = NEW.orden_id AND estado = 'exitoso') THEN
        RAISE EXCEPTION 'RN-04: no hay pago exitoso para la orden';
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_venta_exige_pago BEFORE INSERT ON venta
    FOR EACH ROW EXECUTE FUNCTION f_venta_exige_pago();


-- RN-13 · El método de la venta es el del pago que la respalda.
--
-- Hueco detectado por las pruebas: nada impedía cobrar en EFECTIVO y
-- registrar la venta como 'manual'. El cuadre de caja se calcula sobre
-- venta.metodo, así que ese dinero desaparecía del efectivo esperado y
-- el turno cerraba con un sobrante inexplicable.
CREATE FUNCTION f_venta_metodo_coincide() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE v_metodo text;
BEGIN
    SELECT metodo INTO v_metodo FROM pago
    WHERE orden_id = NEW.orden_id AND estado = 'exitoso';
    IF NEW.metodo <> v_metodo THEN
        RAISE EXCEPTION 'RN-13: la venta dice % pero el pago fue %',
            NEW.metodo, v_metodo;
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_venta_metodo BEFORE INSERT ON venta
    FOR EACH ROW EXECUTE FUNCTION f_venta_metodo_coincide();


-- RN-05 · El pago iguala el monto de la orden.
CREATE FUNCTION f_pago_monto() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE v_monto centimos;
BEGIN
    SELECT monto_centimos INTO v_monto FROM orden WHERE id = NEW.orden_id;
    IF NEW.monto_centimos <> v_monto THEN
        RAISE EXCEPTION 'RN-05: el pago (%) no coincide con la orden (%)',
            NEW.monto_centimos, v_monto;
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_pago_monto BEFORE INSERT ON pago
    FOR EACH ROW EXECUTE FUNCTION f_pago_monto();


-- RN-06 · La venta es INMUTABLE. Para revertirla existe `anulacion`.
CREATE FUNCTION f_inmutable() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION 'RN-06: los registros de % no se eliminan', TG_TABLE_NAME;
    END IF;
    RAISE EXCEPTION 'RN-06: los registros de % son inmutables', TG_TABLE_NAME;
END $$;

CREATE TRIGGER trg_venta_inmutable BEFORE UPDATE OF
    turno_id, usuario_id, ficha_id, orden_id, plan_id, cliente_id,
    metodo, monto_centimos, fecha_local, ocurrida_en ON venta
    FOR EACH ROW EXECUTE FUNCTION f_inmutable();

CREATE TRIGGER trg_venta_no_borrar BEFORE DELETE ON venta
    FOR EACH ROW EXECUTE FUNCTION f_inmutable();

CREATE TRIGGER trg_anulacion_no_borrar BEFORE DELETE ON anulacion
    FOR EACH ROW EXECUTE FUNCTION f_inmutable();

CREATE TRIGGER trg_pago_no_borrar BEFORE DELETE ON pago
    FOR EACH ROW EXECUTE FUNCTION f_inmutable();


-- RN-07 · Un pago resuelto no retrocede. Un exitoso solo puede devolverse.
CREATE FUNCTION f_pago_estado_final() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF OLD.estado <> 'pendiente' AND NEW.estado <> OLD.estado
       AND NOT (OLD.estado = 'exitoso' AND NEW.estado = 'devuelto') THEN
        RAISE EXCEPTION 'RN-07: un pago % no puede pasar a %', OLD.estado, NEW.estado;
    END IF;

    -- RN-08 · La conciliación es DEFINITIVA: una que se puede borrar no
    -- demuestra nada.
    IF OLD.conciliado_en IS NOT NULL
       AND (NEW.conciliado_en IS DISTINCT FROM OLD.conciliado_en
         OR NEW.conciliado_por IS DISTINCT FROM OLD.conciliado_por) THEN
        RAISE EXCEPTION 'RN-08: el pago ya fue conciliado';
    END IF;

    -- RN-09 · Concilia un supervisor. Quien cobra no se audita a sí mismo.
    IF NEW.conciliado_por IS NOT NULL AND OLD.conciliado_por IS NULL THEN
        IF COALESCE((SELECT rol FROM usuario WHERE id = NEW.conciliado_por), '')
           NOT IN ('supervisor','admin') THEN
            RAISE EXCEPTION 'RN-09: solo un supervisor concilia pagos';
        END IF;
        IF NEW.conciliado_por = NEW.confirmado_por THEN
            RAISE EXCEPTION 'RN-09: quien cobro el pago no puede conciliarlo';
        END IF;
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_pago_estado BEFORE UPDATE ON pago
    FOR EACH ROW EXECUTE FUNCTION f_pago_estado_final();


-- RN-10 · La referencia del POS calza con el formato del voucher.
-- Va en trigger y no en CHECK porque el patrón vive en otra tabla.
CREATE FUNCTION f_pago_ref_patron() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE v_patron text;
BEGIN
    IF NEW.motivo_manual = 'pos_externo' THEN
        SELECT p.ref_patron_pos INTO v_patron
        FROM orden o JOIN turno t ON t.id = o.turno_id
        JOIN punto p ON p.id = t.punto_id
        WHERE o.id = NEW.orden_id;
        IF v_patron IS NOT NULL AND NEW.referencia !~ v_patron THEN
            RAISE EXCEPTION 'RN-10: la referencia no tiene el formato del voucher del POS';
        END IF;
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_pago_ref_patron BEFORE INSERT ON pago
    FOR EACH ROW EXECUTE FUNCTION f_pago_ref_patron();


-- RN-11 · Toda operación ocurre en un turno ABIERTO.
CREATE FUNCTION f_turno_abierto() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF (SELECT cerrado_en FROM turno WHERE id = NEW.turno_id) IS NOT NULL THEN
        RAISE EXCEPTION 'RN-11: el turno ya esta cerrado';
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_venta_turno_abierto BEFORE INSERT ON venta
    FOR EACH ROW EXECUTE FUNCTION f_turno_abierto();
CREATE TRIGGER trg_anulacion_turno_abierto BEFORE INSERT ON anulacion
    FOR EACH ROW EXECUTE FUNCTION f_turno_abierto();
CREATE TRIGGER trg_movimiento_turno_abierto BEFORE INSERT ON movimiento_caja
    FOR EACH ROW EXECUTE FUNCTION f_turno_abierto();


-- RN-12 · Un turno cerrado no se reabre ni se modifica.
CREATE FUNCTION f_turno_cerrado() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF OLD.cerrado_en IS NOT NULL THEN
        RAISE EXCEPTION 'RN-12: el turno ya fue cerrado';
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_turno_cerrado BEFORE UPDATE ON turno
    FOR EACH ROW EXECUTE FUNCTION f_turno_cerrado();


-- El número de orden lo asigna la base, no la aplicación.
CREATE FUNCTION f_orden_numero() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.numero IS NULL THEN
        NEW.numero := siguiente_numero_orden(NEW.comercio_id);
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_orden_numero BEFORE INSERT ON orden
    FOR EACH ROW EXECUTE FUNCTION f_orden_numero();

ALTER TABLE orden ALTER COLUMN numero DROP NOT NULL;


-- ═══════════════════════════════════════════════════════════════════════
--  VISTAS
-- ═══════════════════════════════════════════════════════════════════════

-- Todas las ventas MENOS las anuladas. Todos los reportes de dinero
-- parten de aquí: centralizar la decisión evita que una consulta olvide
-- el filtro, que es exactamente lo que pasaba en la versión anterior.
CREATE VIEW v_venta_vigente AS
SELECT v.* FROM venta v
WHERE NOT EXISTS (SELECT 1 FROM anulacion a WHERE a.venta_id = v.id);


-- Stock por plan. El orden importa: se CUENTA primero sobre el índice
-- parcial y se une DESPUÉS. Unir antes de agrupar era 11 veces más lento.
CREATE VIEW v_pool AS
WITH disp AS (
    SELECT comercio_id, plan_id, count(*) AS n FROM ficha
    WHERE estado = 'disponible' AND en_router
    GROUP BY comercio_id, plan_id
), pend AS (
    SELECT comercio_id, plan_id, count(*) AS n FROM ficha
    WHERE estado = 'disponible' AND NOT en_router
    GROUP BY comercio_id, plan_id
)
SELECT p.comercio_id, p.id AS plan_id, p.codigo, p.nombre, p.categoria,
       p.precio_centimos,
       COALESCE(d.n, 0)::integer  AS disponibles,
       COALESCE(pe.n, 0)::integer AS sin_cargar,
       COALESCE(p.stock_minimo,
                (SELECT min(pool_minimo) FROM punto pt
                 WHERE pt.comercio_id = p.comercio_id AND pt.activo)) AS minimo
FROM plan p
LEFT JOIN disp d  ON d.plan_id  = p.id
LEFT JOIN pend pe ON pe.plan_id = p.id
WHERE p.activo;


-- Stock por lote, para la pantalla de inventario.
CREATE VIEW v_stock_lote AS
SELECT l.comercio_id, l.id AS lote_id, l.plan_id, p.nombre AS plan,
       l.cantidad, l.importacion_id, i.archivo, l.creado_en, l.anulado_en,
       count(*) FILTER (WHERE f.estado = 'disponible' AND f.en_router)     AS disponibles,
       count(*) FILTER (WHERE f.estado = 'disponible' AND NOT f.en_router) AS sin_cargar,
       count(*) FILTER (WHERE f.estado = 'reservada')                      AS reservadas,
       count(*) FILTER (WHERE f.estado IN ('vendida','activada','agotada','expirada')) AS vendidas,
       count(*) FILTER (WHERE f.estado = 'anulada')                        AS anuladas
FROM lote l
JOIN plan p ON p.id = l.plan_id
LEFT JOIN importacion i ON i.id = l.importacion_id
LEFT JOIN ficha f ON f.lote_id = l.id
GROUP BY l.comercio_id, l.id, l.plan_id, p.nombre, l.cantidad,
         l.importacion_id, i.archivo, l.creado_en, l.anulado_en;


-- Estado del turno abierto.
--
-- ⚠ El cuadre sigue al DINERO FÍSICO, no a las ventas vigentes:
--     esperado = fondo + todo lo cobrado − lo devuelto + movimientos
-- Usar ventas vigentes descontaría DOS VECES una venta anulada en el
-- mismo turno: una al excluirla y otra al restar la devolución.
CREATE VIEW v_turno_actual AS
SELECT t.comercio_id, t.id AS turno_id, t.punto_id, t.dia_operativo,
       u.nombre AS usuario, t.abierto_en, t.fondo_inicial,
       COALESCE((SELECT sum(v.monto_centimos) FROM venta v
                 WHERE v.turno_id = t.id AND v.metodo = 'efectivo'), 0) AS efectivo_cobrado,
       COALESCE((SELECT sum(v.monto_centimos) FROM anulacion a
                 JOIN venta v ON v.id = a.venta_id
                 WHERE a.turno_id = t.id AND v.metodo = 'efectivo'), 0) AS efectivo_devuelto,
       COALESCE((SELECT sum(m.monto_centimos) FROM movimiento_caja m
                 WHERE m.turno_id = t.id AND m.tipo <> 'fondo'), 0) AS movimientos,
       t.fondo_inicial
         + COALESCE((SELECT sum(v.monto_centimos) FROM venta v
                     WHERE v.turno_id = t.id AND v.metodo = 'efectivo'), 0)
         - COALESCE((SELECT sum(v.monto_centimos) FROM anulacion a
                     JOIN venta v ON v.id = a.venta_id
                     WHERE a.turno_id = t.id AND v.metodo = 'efectivo'), 0)
         + COALESCE((SELECT sum(m.monto_centimos) FROM movimiento_caja m
                     WHERE m.turno_id = t.id AND m.tipo <> 'fondo'), 0) AS efectivo_esperado,
       (SELECT count(*) FROM v_venta_vigente v WHERE v.turno_id = t.id) AS fichas,
       (SELECT count(*) FROM pago pg JOIN orden o ON o.id = pg.orden_id
         WHERE o.turno_id = t.id AND pg.motivo_manual = 'pos_externo'
           AND pg.estado = 'exitoso') AS pagos_pos
FROM turno t
JOIN usuario u ON u.id = t.usuario_id
WHERE t.cerrado_en IS NULL;


-- Lista de trabajo del supervisor: pagos del POS que nadie verificó.
CREATE VIEW v_pendiente_conciliar AS
SELECT pg.comercio_id, pg.id AS pago_id, t.dia_operativo, u.nombre AS usuario,
       pg.medio, pg.referencia, pg.monto_centimos, pg.resuelto_en AS desde, o.numero
FROM pago pg
JOIN orden o   ON o.id = pg.orden_id
JOIN turno t   ON t.id = o.turno_id
JOIN usuario u ON u.id = o.usuario_id
WHERE pg.metodo = 'manual' AND pg.estado = 'exitoso' AND pg.conciliado_en IS NULL;


-- ── Alarmas: DEBEN devolver cero filas siempre ──────────────────────
CREATE VIEW v_alarma_sin_pago AS
SELECT v.comercio_id, v.id AS venta_id FROM v_venta_vigente v
WHERE NOT EXISTS (SELECT 1 FROM pago pg
                  WHERE pg.orden_id = v.orden_id AND pg.estado = 'exitoso');

-- Se cobró y no se entregó: la más grave.
CREATE VIEW v_alarma_sin_venta AS
SELECT pg.comercio_id, pg.id AS pago_id FROM pago pg
JOIN orden o ON o.id = pg.orden_id
WHERE pg.estado = 'exitoso' AND o.estado = 'pagada'
  AND NOT EXISTS (SELECT 1 FROM venta v WHERE v.orden_id = pg.orden_id);

-- Ficha vendida que no está en el router: el cliente pagó por un código
-- que no funciona.
CREATE VIEW v_alarma_codigo_muerto AS
SELECT f.comercio_id, f.id AS ficha_id, f.codigo FROM ficha f
WHERE f.estado IN ('vendida','activada') AND NOT f.en_router;

-- Consumo en una ficha no vendida: código filtrado, o una ficha anulada
-- que no se deshabilitó en el router.
CREATE VIEW v_alarma_fuga_pool AS
SELECT f.comercio_id, f.id AS ficha_id, f.codigo, c.uptime_seg
FROM ficha f JOIN consumo c ON c.ficha_id = f.id
WHERE f.estado IN ('disponible','reservada','anulada')
  AND (c.uptime_seg > 0 OR c.bytes_in > 0);


-- ═══════════════════════════════════════════════════════════════════════
--  SEGURIDAD A NIVEL DE FILA
--
--  El aislamiento entre comercios NO depende de que el programador
--  recuerde filtrar. Aunque una consulta olvide el WHERE, la base no
--  devuelve datos de otro comercio.
-- ═══════════════════════════════════════════════════════════════════════

DO $$
DECLARE t text;
BEGIN
    FOREACH t IN ARRAY ARRAY[
        'punto','plan','usuario','turno','movimiento_caja','cliente',
        'importacion','lote','ficha','orden','pago','venta','anulacion',
        'entrega','incidencia','intento_venta','stock_cierre','consumo','auditoria'
    ] LOOP
        EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
        -- FORCE hace que la política aplique también al dueño de la tabla:
        -- sin esto, el usuario propietario la saltaría por completo.
        EXECUTE format('ALTER TABLE %I FORCE ROW LEVEL SECURITY', t);
        EXECUTE format(
            'CREATE POLICY aislamiento ON %I USING (comercio_id = app_comercio())
             WITH CHECK (comercio_id = app_comercio())', t);
    END LOOP;
END $$;


-- Rol de la aplicación. No es dueño de las tablas, así que las políticas
-- lo alcanzan siempre.
-- Los roles viven a nivel del servidor, no de la base: crearlo sin
-- condición rompe la segunda base del mismo servidor (pruebas, staging).
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_fichas') THEN
        CREATE ROLE app_fichas NOLOGIN;
    END IF;
END $$;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA public TO app_fichas;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO app_fichas;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO app_fichas;
-- Nadie borra: las correcciones se hacen con anulaciones, no con DELETE.
REVOKE DELETE ON ALL TABLES IN SCHEMA public FROM app_fichas;
